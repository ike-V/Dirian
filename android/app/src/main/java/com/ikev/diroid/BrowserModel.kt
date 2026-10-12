package com.ikev.diroid

import android.app.Application
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.FileProvider
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.io.IOException
import java.io.InputStream

/** Why nothing can be listed, shown centered in place of the file list. */
class Problem(val title: String, val detail: String)

private val notConnected = Problem(
    "Not connected to your Mac",
    "Plug in the cable and open Diroid on your Mac. Click Share Mac to Android… at the bottom of its window, then press Start Sharing.",
)

class BrowserModel(private val app: Application) : AndroidViewModel(app) {
    private val prefs = app.getSharedPreferences("session", Context.MODE_PRIVATE)
    private var client: MacClient? = prefs.getString("token", null)
        ?.let { MacClient(it, prefs.getInt("port", 47615)) }

    /** Current folder, relative to the shared folder ("" is the root). */
    var path by mutableStateOf("")
        private set
    var entries by mutableStateOf<List<Entry>>(emptyList())
        private set
    var rootName by mutableStateOf("Mac")
        private set
    var problem by mutableStateOf<Problem?>(null)
        private set
    /** True once the Mac has answered, until a request fails to reach it. */
    var connected by mutableStateOf(false)
        private set
    private var busyCount by mutableIntStateOf(0)
    val busy get() = busyCount > 0

    /** Shown in an alert until dismissed. */
    var error by mutableStateOf<String?>(null)
    /** Shown briefly in a snackbar. */
    var message by mutableStateOf<String?>(null)

    // Set just before launching the system file pickers.
    var pendingSave: Entry? = null
    var pendingSaveMoves = false
    var moveAfterUpload = false

    init {
        if (client == null) problem = notConnected else load("")
    }

    /** Called with the token Diroid on the Mac passes when it opens this app. */
    fun connect(token: String, port: Int) {
        generation++
        prefs.edit().putString("token", token).putInt("port", port).apply()
        client = MacClient(token, port)
        load("")
    }

    /** Bumped on every new token so a stale in-flight request can't report an error over the new session. */
    private var generation = 0

    private fun child(name: String, base: String = path) = if (base.isEmpty()) name else "$base/$name"

    private fun perform(block: suspend (MacClient) -> Unit) {
        val active = client
        if (active == null) {
            problem = notConnected
            return
        }
        val started = generation
        viewModelScope.launch {
            busyCount++
            try {
                block(active)
            } catch (e: Exception) {
                if (started == generation) report(e)
            } finally {
                busyCount--
            }
        }
    }

    private fun report(e: Exception) {
        if (e is IOException || (e is MacException && e.status == 401)) connected = false
        when {
            e is MacException && e.status == 401 -> problem = Problem(
                "Sharing was restarted",
                "Press Start Sharing in Diroid on your Mac again.",
            )
            e is IOException -> problem = notConnected
            e is ActivityNotFoundException -> error = "No app on this device can open that file. Use Save to… instead."
            else -> error = e.message ?: e.toString()
        }
    }

    private suspend fun <T> io(block: () -> T): T = withContext(Dispatchers.IO) { block() }

    fun load(target: String) = perform { client ->
        val fetched = io { client.list(target) }
        entries = fetched
        path = target
        problem = null
        connected = true
        if (target.isEmpty()) rootName = io { runCatching { client.info() }.getOrDefault(rootName) }
    }

    fun refresh() = load(path)

    fun canGoUp() = path.isNotEmpty()

    fun goUp() = load(path.substringBeforeLast('/', ""))

    /** Opens a folder, or pulls a file to the cache and opens it with the default app. */
    fun open(entry: Entry) {
        if (entry.isDirectory) {
            load(child(entry.name))
            return
        }
        val source = child(entry.name)
        perform { client ->
            val file = io {
                val dir = File(app.cacheDir, "open").apply { deleteRecursively(); mkdirs() }
                File(dir, entry.name).also { target -> target.outputStream().use { client.download(source, it) } }
            }
            val uri = FileProvider.getUriForFile(app, "${app.packageName}.files", file)
            val mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(file.extension.lowercase()) ?: "*/*"
            app.startActivity(
                Intent(Intent.ACTION_VIEW)
                    .setDataAndType(uri, mime)
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        }
    }

    /** Copies the file chosen in `pendingSave` to `uri`; deletes it from the Mac afterwards when moving. */
    fun saveTo(uri: Uri) {
        val entry = pendingSave ?: return
        val move = pendingSaveMoves
        pendingSave = null
        val source = child(entry.name)
        perform { client ->
            io {
                val output = app.contentResolver.openOutputStream(uri) ?: throw IOException("cannot write there")
                output.use { client.download(source, it) }
            }
            if (move) {
                io { client.delete(source) }
                load(path)
            }
            message = if (move) "Moved ${entry.name} to this device" else "Saved ${entry.name}"
        }
    }

    /** Pushes picked files into the current folder, renaming on collision; deletes the originals when moving. */
    fun upload(uris: List<Uri>) {
        val base = path
        val taken = entries.mapTo(mutableSetOf()) { it.name }
        val move = moveAfterUpload
        perform { client ->
            val failures = mutableListOf<String>()
            var sent = 0
            for (uri in uris) {
                val (name, size) = describe(uri)
                try {
                    val unique = uniqueName(name) { it in taken }
                    taken += unique
                    io { uploadOne(client, child(unique, base), uri, size) }
                    sent++
                    if (move) runCatching { DocumentsContract.deleteDocument(app.contentResolver, uri) }
                } catch (e: Exception) {
                    failures += "$name: ${e.message}"
                }
            }
            load(base)
            if (failures.isNotEmpty()) error = failures.joinToString("\n")
            else message = "Uploaded $sent ${if (sent == 1) "file" else "files"}"
        }
    }

    private fun uploadOne(client: MacClient, target: String, uri: Uri, size: Long) {
        val resolver = app.contentResolver
        if (size >= 0) {
            val input = resolver.openInputStream(uri) ?: throw IOException("cannot read file")
            input.use { client.upload(target, it, size) }
        } else {
            // Unknown size: spool to the cache first, since the server needs a Content-Length.
            val spool = File.createTempFile("upload", null, app.cacheDir)
            try {
                resolver.openInputStream(uri)?.use { it.copyTo(spool.outputStream()) } ?: throw IOException("cannot read file")
                spool.inputStream().use { client.upload(target, it as InputStream, spool.length()) }
            } finally {
                spool.delete()
            }
        }
    }

    private fun describe(uri: Uri): Pair<String, Long> {
        app.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val name = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME).takeIf { it >= 0 }?.let(cursor::getString)
                val size = cursor.getColumnIndex(OpenableColumns.SIZE).takeIf { it >= 0 && !cursor.isNull(it) }?.let(cursor::getLong)
                return (name ?: uri.lastPathSegment ?: "file") to (size ?: -1L)
            }
        }
        return (uri.lastPathSegment ?: "file") to -1L
    }

    fun makeDirectory(name: String) = perform { client ->
        io { client.makeDirectory(child(name)) }
        load(path)
    }

    fun rename(entry: Entry, newName: String) = perform { client ->
        io { client.rename(child(entry.name), child(newName)) }
        load(path)
    }

    fun delete(entry: Entry) = perform { client ->
        io { client.delete(child(entry.name)) }
        load(path)
        message = "Moved ${entry.name} to the Mac's Trash"
    }
}

/** Appends " (1)", " (2)", ... before the extension until `exists` reports the name is free. */
fun uniqueName(original: String, exists: (String) -> Boolean): String {
    if (!exists(original)) return original
    val base = original.substringBeforeLast('.', original)
    val extension = if (original.contains('.')) "." + original.substringAfterLast('.') else ""
    var counter = 1
    while (true) {
        val candidate = "$base ($counter)$extension"
        if (!exists(candidate)) return candidate
        counter++
    }
}
