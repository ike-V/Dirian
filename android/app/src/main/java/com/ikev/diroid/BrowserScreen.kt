package com.ikev.diroid

import android.text.format.Formatter
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.InsertDriveFile
import androidx.compose.material.icons.automirrored.filled.ViewList
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.automirrored.filled.Sort
import androidx.compose.material.icons.filled.Upload
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.text.DateFormat
import java.util.Date

val AndroidGreen = Color(0xFF3DDC84)
private val Background = Color(0xFF1A1A1A)

@Composable
fun DiroidTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = darkColorScheme(
            primary = AndroidGreen,
            onPrimary = Color.Black,
            primaryContainer = AndroidGreen,
            onPrimaryContainer = Color.Black,
            background = Background,
            onBackground = Color(0xFFEDEDED),
            surface = Background,
            onSurface = Color(0xFFEDEDED),
            surfaceVariant = Color(0xFF2A2A2A),
            onSurfaceVariant = Color(0xFFA6A6A6),
            surfaceContainer = Color(0xFF262626),
            surfaceContainerHigh = Color(0xFF2C2C2C),
        ),
        content = content,
    )
}

/** What the entry menus and taps can do; implemented by the screen. */
private class EntryActions(
    val open: (Entry) -> Unit,
    val rename: (Entry) -> Unit,
    val saveTo: (Entry, Boolean) -> Unit,
    val delete: (Entry) -> Unit,
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BrowserScreen(
    model: BrowserModel,
    onPickUpload: (deleteAfter: Boolean) -> Unit,
    onPickSave: (Entry, move: Boolean) -> Unit,
) {
    var grid by rememberSaveable { mutableStateOf(false) }
    var groupBy by rememberSaveable { mutableStateOf(GroupBy.None) }
    var groupMenu by remember { mutableStateOf(false) }
    var uploadMenu by remember { mutableStateOf(false) }
    var overflow by remember { mutableStateOf(false) }
    var renaming by remember { mutableStateOf<Entry?>(null) }
    var deleting by remember { mutableStateOf<Entry?>(null) }
    var creatingFolder by remember { mutableStateOf(false) }
    val snackbar = remember { SnackbarHostState() }

    BackHandler(enabled = model.canGoUp()) { model.goUp() }
    LaunchedEffect(model.message) {
        model.message?.let {
            snackbar.showSnackbar(it)
            model.message = null
        }
    }

    val actions = remember {
        EntryActions(
            open = model::open,
            rename = { renaming = it },
            saveTo = onPickSave,
            delete = { deleting = it },
        )
    }

    Scaffold(
        containerColor = Background,
        snackbarHost = { SnackbarHost(snackbar) },
        topBar = {
            TopAppBar(
                colors = TopAppBarDefaults.topAppBarColors(containerColor = Background),
                navigationIcon = {
                    if (model.canGoUp()) {
                        IconButton(onClick = model::goUp) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Up") }
                    }
                },
                title = {
                    Column {
                        Text(model.rootName, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        if (model.connected) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Box(Modifier.size(8.dp).background(AndroidGreen, CircleShape))
                                Spacer(Modifier.width(6.dp))
                                Text("Connected over USB", fontSize = 12.sp, color = AndroidGreen)
                            }
                        }
                    }
                },
                actions = {
                    IconButton(onClick = { grid = !grid }) {
                        if (grid) Icon(Icons.AutoMirrored.Filled.ViewList, "List view")
                        else Icon(Icons.Filled.GridView, "Grid view")
                    }
                    Box {
                        IconButton(onClick = { groupMenu = true }) { Icon(Icons.AutoMirrored.Filled.Sort, "Group by") }
                        DropdownMenu(expanded = groupMenu, onDismissRequest = { groupMenu = false }) {
                            GroupBy.entries.forEach { option ->
                                DropdownMenuItem(
                                    text = {
                                        Text(option.label, color = if (option == groupBy) AndroidGreen else Color.Unspecified)
                                    },
                                    onClick = {
                                        groupBy = option
                                        groupMenu = false
                                    },
                                )
                            }
                        }
                    }
                    Box {
                        IconButton(onClick = { overflow = true }) { Icon(Icons.Filled.MoreVert, "More") }
                        DropdownMenu(expanded = overflow, onDismissRequest = { overflow = false }) {
                            DropdownMenuItem(
                                text = { Text("Refresh") },
                                onClick = {
                                    overflow = false
                                    model.refresh()
                                },
                            )
                            DropdownMenuItem(
                                text = { Text("New Folder…") },
                                enabled = model.problem == null,
                                onClick = {
                                    overflow = false
                                    creatingFolder = true
                                },
                            )
                        }
                    }
                },
            )
        },
        floatingActionButton = {
            if (model.problem == null) {
                Box {
                    ExtendedFloatingActionButton(
                        onClick = { uploadMenu = true },
                        icon = { Icon(Icons.Filled.Upload, null) },
                        text = { Text("Upload") },
                    )
                    DropdownMenu(expanded = uploadMenu, onDismissRequest = { uploadMenu = false }) {
                        DropdownMenuItem(
                            text = { Text("Copy files to the Mac") },
                            onClick = {
                                uploadMenu = false
                                onPickUpload(false)
                            },
                        )
                        DropdownMenuItem(
                            text = { Text("Move files to the Mac") },
                            onClick = {
                                uploadMenu = false
                                onPickUpload(true)
                            },
                        )
                    }
                }
            }
        },
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize()) {
            if (model.problem == null) Breadcrumb(model.rootName, model.path, model::load)
            Box(Modifier.weight(1f).fillMaxWidth()) {
                val problem = model.problem
                val groups = groupEntries(model.entries, groupBy)
                when {
                    problem != null -> ProblemView(problem, onRetry = model::refresh)
                    model.entries.isEmpty() && !model.busy -> CenteredText("This folder is empty")
                    grid -> GridContent(groups, actions)
                    else -> ListContent(groups, actions)
                }
                if (model.busy) {
                    LinearProgressIndicator(
                        modifier = Modifier.fillMaxWidth().align(Alignment.TopCenter),
                        color = AndroidGreen,
                    )
                }
            }
        }
    }

    if (creatingFolder) {
        val existing = model.entries.mapTo(mutableSetOf()) { it.name }
        TextDialog(
            title = "New Folder",
            confirm = "Create",
            initial = uniqueName("New Folder") { it in existing },
            onDismiss = { creatingFolder = false },
            onConfirm = {
                creatingFolder = false
                model.makeDirectory(it)
            },
        )
    }
    renaming?.let { entry ->
        TextDialog(
            title = "Rename \"${entry.name}\"",
            confirm = "Rename",
            initial = entry.name,
            onDismiss = { renaming = null },
            onConfirm = {
                renaming = null
                if (it != entry.name) model.rename(entry, it)
            },
        )
    }
    deleting?.let { entry ->
        AlertDialog(
            onDismissRequest = { deleting = null },
            title = { Text(if (entry.isDirectory) "Delete \"${entry.name}\" and everything inside it?" else "Delete \"${entry.name}\"?") },
            text = { Text("It moves to the Mac's Trash, where you can restore it.") },
            confirmButton = {
                TextButton(onClick = {
                    deleting = null
                    model.delete(entry)
                }) { Text("Delete", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = { deleting = null }) { Text("Cancel") } },
        )
    }
    model.error?.let { message ->
        AlertDialog(
            onDismissRequest = { model.error = null },
            title = { Text("Error") },
            text = { Text(message) },
            confirmButton = { TextButton(onClick = { model.error = null }) { Text("OK") } },
        )
    }
}

@Composable
private fun Breadcrumb(rootName: String, path: String, onNavigate: (String) -> Unit) {
    val parts = path.split('/').filter { it.isNotEmpty() }
    val segments = listOf(rootName to "") + parts.mapIndexed { index, part ->
        part to parts.take(index + 1).joinToString("/")
    }
    LazyRow(
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        itemsIndexed(segments) { index, (label, target) ->
            if (index > 0) Text("/", color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(horizontal = 4.dp))
            Text(
                label,
                color = if (index == segments.lastIndex) AndroidGreen else MaterialTheme.colorScheme.onSurface,
                fontSize = 14.sp,
                modifier = Modifier.clickable { onNavigate(target) }.padding(vertical = 8.dp),
            )
        }
    }
}

@Composable
private fun ListContent(groups: List<EntryGroup>, actions: EntryActions) {
    LazyColumn(contentPadding = PaddingValues(bottom = 96.dp)) {
        groups.forEach { group ->
            if (group.title.isNotEmpty()) item(key = "header:${group.title}") { GroupHeader(group.title) }
            items(group.entries, key = { "${group.title}/${it.name}" }) { EntryRow(it, actions) }
        }
    }
}

@Composable
private fun GridContent(groups: List<EntryGroup>, actions: EntryActions) {
    LazyVerticalGrid(
        columns = GridCells.Adaptive(96.dp),
        contentPadding = PaddingValues(start = 8.dp, end = 8.dp, bottom = 96.dp),
    ) {
        groups.forEach { group ->
            if (group.title.isNotEmpty()) {
                item(key = "header:${group.title}", span = { GridItemSpan(maxLineSpan) }) { GroupHeader(group.title) }
            }
            items(group.entries, key = { "${group.title}/${it.name}" }) { EntryCell(it, actions) }
        }
    }
}

@Composable
private fun GroupHeader(title: String) {
    Text(
        title,
        style = MaterialTheme.typography.titleSmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.fillMaxWidth().padding(start = 16.dp, top = 16.dp, bottom = 4.dp),
    )
}

@Composable
private fun EntryIcon(entry: Entry, size: androidx.compose.ui.unit.Dp) {
    if (entry.isDirectory) {
        Icon(Icons.Filled.Folder, null, tint = AndroidGreen, modifier = Modifier.size(size))
    } else {
        Icon(
            Icons.AutoMirrored.Filled.InsertDriveFile, null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(size),
        )
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun EntryRow(entry: Entry, actions: EntryActions) {
    var menu by remember { mutableStateOf(false) }
    val context = LocalContext.current
    Box {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .combinedClickable(onClick = { actions.open(entry) }, onLongClick = { menu = true })
                .padding(start = 16.dp, top = 8.dp, bottom = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            EntryIcon(entry, 28.dp)
            Spacer(Modifier.width(16.dp))
            Column(Modifier.weight(1f)) {
                Text(entry.name, maxLines = 1, overflow = TextOverflow.Ellipsis)
                val date = DateFormat.getDateInstance(DateFormat.MEDIUM).format(Date(entry.modified * 1000))
                val detail = if (entry.isDirectory) date else "${Formatter.formatShortFileSize(context, entry.size)} · $date"
                Text(detail, fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            IconButton(onClick = { menu = true }) {
                Icon(Icons.Filled.MoreVert, "Actions", tint = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        EntryMenu(menu, entry, actions) { menu = false }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun EntryCell(entry: Entry, actions: EntryActions) {
    var menu by remember { mutableStateOf(false) }
    Box {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .combinedClickable(onClick = { actions.open(entry) }, onLongClick = { menu = true })
                .padding(vertical = 10.dp, horizontal = 4.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            EntryIcon(entry, 48.dp)
            Text(
                entry.name,
                fontSize = 12.sp,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                textAlign = TextAlign.Center,
            )
        }
        EntryMenu(menu, entry, actions) { menu = false }
    }
}

@Composable
private fun EntryMenu(expanded: Boolean, entry: Entry, actions: EntryActions, onDismiss: () -> Unit) {
    DropdownMenu(expanded = expanded, onDismissRequest = onDismiss) {
        DropdownMenuItem(text = { Text("Rename…") }, onClick = { onDismiss(); actions.rename(entry) })
        if (!entry.isDirectory) {
            DropdownMenuItem(text = { Text("Save to…") }, onClick = { onDismiss(); actions.saveTo(entry, false) })
            DropdownMenuItem(text = { Text("Move to phone…") }, onClick = { onDismiss(); actions.saveTo(entry, true) })
        }
        DropdownMenuItem(
            text = { Text("Delete", color = MaterialTheme.colorScheme.error) },
            onClick = { onDismiss(); actions.delete(entry) },
        )
    }
}

@Composable
private fun TextDialog(title: String, confirm: String, initial: String, onDismiss: () -> Unit, onConfirm: (String) -> Unit) {
    var text by remember { mutableStateOf(initial) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = { OutlinedTextField(value = text, onValueChange = { text = it }, singleLine = true) },
        confirmButton = {
            TextButton(enabled = text.isNotBlank(), onClick = { onConfirm(text.trim()) }) { Text(confirm) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

@Composable
private fun ProblemView(problem: Problem, onRetry: () -> Unit) {
    Column(
        Modifier.fillMaxSize().padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text(problem.title, style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center)
        Spacer(Modifier.size(8.dp))
        Text(
            problem.detail,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            fontSize = 14.sp,
            textAlign = TextAlign.Center,
        )
        Spacer(Modifier.size(16.dp))
        TextButton(onClick = onRetry) { Text("Try again", color = AndroidGreen) }
    }
}

@Composable
private fun CenteredText(text: String) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Text(text, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
