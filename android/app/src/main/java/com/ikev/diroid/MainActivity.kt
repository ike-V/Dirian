package com.ikev.diroid

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
            DiroidTheme {
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
                )
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        acceptToken(intent)
    }

    /** Diroid on the Mac opens this app with the access token for the current sharing session. */
    private fun acceptToken(intent: Intent) {
        val token = intent.getStringExtra("token") ?: return
        model.connect(token, intent.getIntExtra("port", 47615))
        intent.removeExtra("token")
    }
}
