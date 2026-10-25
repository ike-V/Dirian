package com.ikev.dirian

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.provider.Settings
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.outlined.RadioButtonUnchecked
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog

/** Whether the setup guide has been shown and closed; it opens by itself until then. */
object GuidePrefs {
    private fun prefs(context: Context) = context.getSharedPreferences("setup", Context.MODE_PRIVATE)
    fun seen(context: Context): Boolean = prefs(context).getBoolean("guideSeen", false)
    fun markSeen(context: Context) = prefs(context).edit().putBoolean("guideSeen", true).apply()
}

/** True while USB debugging is turned on in Developer options. */
fun usbDebuggingOn(context: Context): Boolean =
    Settings.Global.getInt(context.contentResolver, Settings.Global.ADB_ENABLED, 0) == 1

/** True while the phone is plugged into a USB port (a computer, rather than a wall charger). */
fun usbPlugged(context: Context): Boolean {
    val battery = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
    return (battery?.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) ?: 0) and BatteryManager.BATTERY_PLUGGED_USB != 0
}

/** Opens Developer options, or About phone while Developer options isn't unlocked yet. */
fun openDeveloperSettings(context: Context) {
    val intent = Intent(Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    runCatching { context.startActivity(intent) }.onFailure {
        context.startActivity(Intent(Settings.ACTION_DEVICE_INFO_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }
}

/** One step of the setup guide. [done] comes from the real state, so a step ticks as soon as it's true;
 *  [action] is the button label, shown only on the first step that isn't done. */
class SetupStep(val title: String, val detail: String, val done: Boolean, val action: String? = null, val onAction: () -> Unit = {})

/** The setup guide: a list of steps that tick themselves, with a button on the one to do next. */
@Composable
fun SetupGuide(steps: List<SetupStep>, onClose: () -> Unit) {
    val allDone = steps.all { it.done }
    val current = steps.indexOfFirst { !it.done }
    Dialog(onDismissRequest = onClose) {
        Surface(shape = RoundedCornerShape(28.dp), color = MaterialTheme.colorScheme.surfaceContainerHigh) {
            Column(Modifier.padding(24.dp).verticalScroll(rememberScrollState())) {
                Text(if (allDone) "You're all set" else "Set up Dirian", fontSize = 22.sp)
                Spacer(Modifier.height(8.dp))
                Text(
                    if (allDone) "Your Mac's shared folder is open on this phone."
                    else "Dirian for Android shows a folder shared from Dirian on your Mac, over USB.",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(Modifier.height(20.dp))
                steps.forEachIndexed { index, step -> StepRow(step, isCurrent = index == current) }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                    TextButton(onClick = onClose) {
                        Text(if (allDone) "Done" else "Skip for now", color = MaterialTheme.colorScheme.primary)
                    }
                }
            }
        }
    }
}

@Composable
private fun StepRow(step: SetupStep, isCurrent: Boolean) {
    Row(Modifier.fillMaxWidth().padding(vertical = 8.dp)) {
        Icon(
            if (step.done) Icons.Filled.CheckCircle else Icons.Outlined.RadioButtonUnchecked, null,
            tint = if (step.done) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(26.dp),
        )
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) {
            Text(step.title, color = if (step.done) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.onSurface)
            if (!step.done) Text(step.detail, fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (isCurrent && step.action != null) {
                Button(onClick = step.onAction, modifier = Modifier.padding(top = 10.dp)) { Text(step.action) }
            }
        }
    }
}
