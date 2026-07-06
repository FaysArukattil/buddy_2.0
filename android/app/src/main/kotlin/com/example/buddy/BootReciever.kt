package com.example.buddy

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * Automatically starts the NotificationListener service after device boot
 * and ensures transactions detected while app was closed are synced
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
                Log.d(TAG, "📱 Starting NotificationListener service...")
                
                try {
                    val serviceIntent = Intent(context, NotificationListener::class.java)
                    
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        context.startForegroundService(serviceIntent)
                    } else {
                        context.startService(serviceIntent)
                    }
                    
                    Log.d(TAG, "✅ NotificationListener service started")
                    Log.d(TAG, "ℹ️  Service will sync any unsynced transactions when Flutter connects")
                } catch (e: Exception) {
                    Log.e(TAG, "❌ Error starting service: ${e.message}", e)
                }
            }
        }
    }
}