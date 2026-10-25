package com.ikev.dirian

import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import kotlinx.coroutines.delay

class MainActivity : ComponentActivity() {
    private val model: BrowserModel by viewModels()

    // With "move", the picker is asked for write access so the originals can be deleted afterwards.
    private val upload = registerForActivityResult(
        object : ActivityResultContracts.OpenMultipleDocuments() {
            override fun createIntent(context: Context, input: Array<String>): Intent =
                super.createIntent(context, input).also {
                    if (model.moveAfterUpload) it.addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                }
        },
    ) { uris -> if (uris.isNotEmpty()) model.upload(uris) }

    private val save = registerForActivityResult(ActivityResultContracts.CreateDocument("*/*")) { uri ->
        if (uri != null) model.saveTo(uri) else model.pendingSave = null
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(Color.TRANSPARENT),
        )
        acceptToken(intent)
        setContent {
            DirianTheme(model.accent) {
                var showGuide by remember { mutableStateOf(!GuidePrefs.seen(this) && model.problem != null) }
                var tick by remember { mutableIntStateOf(0) }
                // Re-reads the phone's state while the guide is open, so its steps tick by themselves.
                LaunchedEffect(showGuide) {
                    while (showGuide) {
                        delay(1_500)
                        tick++
                    }
                }
                BrowserScreen(
                    model = model,
                    onPickUpload = { deleteAfter ->
                        model.moveAfterUpload = deleteAfter
                        upload.launch(arrayOf("*/*"))
                    },
                    onPickSave = { entry, move ->
                        model.pendingSave = entry
                        model.pendingSaveMoves = move
                        save.launch(entry.name)
                    },
                    onSetupGuide = { showGuide = true },
                )
                if (showGuide) {
                    tick.let {
                        SetupGuide(
                            listOf(
                                SetupStep(
                                    "Turn on USB debugging",
                                    "Open Developer options and turn on USB debugging. If Developer options is missing, open Settings → About phone and tap Build number 7 times.",
                                    done = usbDebuggingOn(this), action = "Open Developer options",
                                    onAction = { openDeveloperSettings(this) },
                                ),
                                SetupStep(
                                    "Plug the phone into your Mac",
                                    "Use a USB cable. If the phone asks to allow USB debugging, tap Allow.",
                                    done = usbPlugged(this),
                                ),
                                SetupStep(
                                    "Share a folder from Dirian",
                                    "Open Dirian on your Mac, click Share Mac to Android in its toolbar and choose a folder to share.",
                                    done = model.connected,
                                ),
                            ),
                            onClose = {
                                GuidePrefs.markSeen(this)
                                showGuide = false
                            },
                        )
                    }
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        acceptToken(intent)
    }

    /** Dirian on the Mac opens this app with the access token for the current sharing session, and its accent color. */
    private fun acceptToken(intent: Intent) {
        val token = intent.getStringExtra("token") ?: return
        model.connect(token, intent.getIntExtra("port", 47615), intent.getStringExtra("accent"))
        intent.removeExtra("token")
    }
}
