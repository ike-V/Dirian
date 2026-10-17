package com.ikev.diroid

import android.net.Uri
import org.json.JSONArray
import org.json.JSONObject
import java.io.InputStream
import java.io.OutputStream
import java.net.HttpURLConnection
import java.net.URL

class MacException(val status: Int, message: String) : Exception(message)

/** Client for Dirian's file server on the Mac, reached through `adb reverse` at 127.0.0.1. */
class MacClient(private val token: String, private val port: Int) {

    private fun open(method: String, endpoint: String, vararg query: Pair<String, String>): HttpURLConnection {
        val queryString = query.joinToString("&") { (key, value) -> "$key=${Uri.encode(value)}" }
        val connection = URL("http://127.0.0.1:$port/$endpoint?$queryString").openConnection() as HttpURLConnection
        connection.requestMethod = method
        connection.setRequestProperty("Authorization", "Bearer $token")
        connection.connectTimeout = 3_000
        connection.readTimeout = 30_000
        return connection
    }

    /** Throws the server's message unless the response is 200. */
    private fun check(connection: HttpURLConnection) {
        val status = connection.responseCode
        if (status == 200) return
        val message = connection.errorStream?.bufferedReader()?.readText().orEmpty()
        connection.disconnect()
        throw MacException(status, message.ifEmpty { "HTTP $status" })
    }

    private fun send(method: String, endpoint: String, vararg query: Pair<String, String>) {
        val connection = open(method, endpoint, *query)
        try {
            check(connection)
        } finally {
            connection.disconnect()
        }
    }

    fun info(): String {
        val connection = open("GET", "info")
        try {
            check(connection)
            return JSONObject(connection.inputStream.bufferedReader().readText()).getString("name")
        } finally {
            connection.disconnect()
        }
    }

    fun list(path: String): List<Entry> {
        val connection = open("GET", "list", "path" to path)
        try {
            check(connection)
            val array = JSONArray(connection.inputStream.bufferedReader().readText())
            return List(array.length()) {
                val item = array.getJSONObject(it)
                Entry(
                    name = item.getString("name"),
                    isDirectory = item.getBoolean("dir"),
                    size = item.getLong("size"),
                    modified = item.getLong("mtime"),
                )
            }
        } finally {
            connection.disconnect()
        }
    }

    fun download(path: String, output: OutputStream) {
        val connection = open("GET", "file", "path" to path)
        try {
            check(connection)
            connection.inputStream.use { it.copyTo(output, 64 * 1024) }
        } finally {
            connection.disconnect()
        }
    }

    /** Streams `length` bytes from `input`; the server refuses to overwrite an existing file. */
    fun upload(path: String, input: InputStream, length: Long) {
        val connection = open("PUT", "file", "path" to path)
        try {
            connection.doOutput = true
            connection.setFixedLengthStreamingMode(length)
            connection.outputStream.use { input.copyTo(it, 64 * 1024) }
            check(connection)
        } finally {
            connection.disconnect()
        }
    }

    fun makeDirectory(path: String) = send("POST", "mkdir", "path" to path)

    fun rename(path: String, to: String) = send("POST", "rename", "path" to path, "to" to to)

    /** Moves the item to the Mac's Trash. */
    fun delete(path: String) = send("DELETE", "file", "path" to path)
}
