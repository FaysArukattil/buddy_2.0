package com.faysarukattil.buddy

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Boot receiver — kept as a no-op safety net.
 *
 * NotificationListenerService is automatically started by the OS
 * after boot if the user has granted notification access permission.
 * This receiver simply logs the event for debugging.
 */
class BootReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "BootReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            "android.intent.action.QUICKBOOT_POWERON",
            Intent.ACTION_MY_PACKAGE_REPLACED -> {
                Log.d(TAG, "📱 Device event: ${intent.action}")
                Log.d(TAG, "ℹ️ NotificationListenerService will be started by the OS automatically")
            }
        }
    }
}