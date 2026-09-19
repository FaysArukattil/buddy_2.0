package com.faysarukattil.buddy

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.util.Log

/**
 * Simplified MainActivity — only provides a MethodChannel for Flutter
 * to check notification listener permission status and read SharedPreferences.
 *
 * The NotificationListenerService is managed entirely by the OS.
 * No manual service start/stop, no instance tracking, no sync handlers.
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "notification_channel"
        private const val TAG = "MainActivity"
    }

    private lateinit var channel: MethodChannel

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        )

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "isNotificationListenerEnabled" -> {
                    // Check if notification listener permission is granted
                    val enabled = isNotificationListenerEnabled()
                    result.success(enabled)
                }
                "getUnsyncedTransactionCount" -> {
                    // Return count of unsynced transactions in SharedPreferences
                    val count = getUnsyncedTransactionCount()
                    result.success(count)
                }
                else -> result.notImplemented()
            }
        }

        Log.d(TAG, "✅ MethodChannel '$CHANNEL' ready")
    }

    private fun isNotificationListenerEnabled(): Boolean {
        val flat = android.provider.Settings.Secure.getString(
            contentResolver,
            "enabled_notification_listeners"
        )
        return flat != null && flat.contains(applicationContext.packageName)
    }

    private fun getUnsyncedTransactionCount(): Int {
        val prefs = getSharedPreferences("buddy_prefs", MODE_PRIVATE)
        return prefs.all.keys.count { it.startsWith("txn_") }
    }

    override fun onDestroy() {
        Log.d(TAG, "🛑 MainActivity destroyed")
        super.onDestroy()
    }
}