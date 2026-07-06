package com.example.buddy

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.util.Log
import android.os.Build
import android.os.Handler
import android.os.Looper

class MainActivity : FlutterActivity() {

    companion object {
        var instance: MainActivity? = null
        private const val CHANNEL = "notification_channel"
        private const val TAG = "MainActivity"
    }

    private lateinit var channel: MethodChannel

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        instance = this

        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        )

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "startNotificationService" -> {
                    Log.d(TAG, "📡 Starting NotificationListener service...")
                    startNotificationListenerService()
                    result.success(true)
                }
                "stopNotificationService" -> {
                    Log.d(TAG, "🛑 Stopping NotificationListener service...")
                    stopNotificationListenerService()
                    result.success(true)
                }
                "getQueuedNotifications" -> {
                    Log.d(TAG, "📬 Requesting queued notifications...")
                    broadcastProcessQueue()
                    result.success(true)
                }
                "syncUnsyncedTransactions" -> {
                    Log.d(TAG, "🔄 Flutter requested unsynced transaction sync...")
                    requestUnsyncedTransactionSync()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        Log.d(TAG, "✅ MethodChannel '$CHANNEL' ready")
        
        // Give Flutter a moment to initialize, then sync unsynced transactions
        Handler(Looper.getMainLooper()).postDelayed({
            broadcastProcessQueue()
            requestUnsyncedTransactionSync()
        }, 1000)
    }

    private fun startNotificationListenerService() {
        try {
            val serviceIntent = Intent(this, NotificationListener::class.java)
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(serviceIntent)
            } else {
                startService(serviceIntent)
            }
            
            Log.d(TAG, "✅ NotificationListener service started")
            
            // Request sync after starting service
            Handler(Looper.getMainLooper()).postDelayed({
                requestUnsyncedTransactionSync()
            }, 500)
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error starting service: ${e.message}", e)
        }
    }

    private fun stopNotificationListenerService() {
        try {
            val serviceIntent = Intent(this, NotificationListener::class.java)
            stopService(serviceIntent)
            Log.d(TAG, "✅ NotificationListener service stopped")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error stopping service: ${e.message}", e)
        }
    }

    private fun broadcastProcessQueue() {
        Log.d(TAG, "📮 Ready to process queued notifications")
    }

    private fun requestUnsyncedTransactionSync() {
        Log.d(TAG, "🔄 Requesting unsynced transaction sync from service...")
        
        try {
            // Send broadcast to NotificationListener to trigger sync
            val syncIntent = Intent("com.example.buddy.SYNC_UNSYNCED_TRANSACTIONS")
            sendBroadcast(syncIntent)
            
            Log.d(TAG, "✅ Sync request broadcast sent")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error requesting sync: ${e.message}", e)
        }
    }

    fun sendNotificationToFlutter(packageName: String, title: String, content: String) {
        Log.d(TAG, "📤 Sending notification to Flutter: $packageName | $title")
        try {
            val map = mapOf(
                "package" to packageName,
                "packageName" to packageName,
                "title" to title,
                "content" to content,
                "text" to content,
                "body" to content
            )
            channel.invokeMethod("onNotificationReceived", map)
            Log.d(TAG, "✅ Notification sent to Flutter successfully")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error sending notification to Flutter: ${e.message}", e)
        }
    }

    fun saveTransactionToDatabase(transactionData: Map<String, Any>) {
        Log.d(TAG, "💾 Saving transaction to database via Flutter")
        Log.d(TAG, "   Data: $transactionData")
        
        try {
            channel.invokeMethod("onTransactionDetected", transactionData)
            Log.d(TAG, "✅ Transaction sent to Flutter for database insert")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error sending transaction to Flutter: ${e.message}", e)
        }
    }

    fun handleDuplicateResponse(hash: String, shouldAdd: Boolean) {
        Log.d(TAG, "📨 Handling duplicate response: hash=$hash, shouldAdd=$shouldAdd")
        
        try {
            val responseData = mapOf(
                "hash" to hash,
                "shouldAdd" to shouldAdd
            )
            
            channel.invokeMethod("onDuplicateResponse", responseData)
            Log.d(TAG, "✅ Response sent to Flutter")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error sending response to Flutter: ${e.message}", e)
        }
    }

    override fun onResume() {
        super.onResume()
        Log.d(TAG, "📱 MainActivity resumed - processing queued notifications")
        
        // Sync unsynced transactions when app resumes
        Handler(Looper.getMainLooper()).postDelayed({
            requestUnsyncedTransactionSync()
        }, 500)
    }

    override fun onDestroy() {
        instance = null
        Log.d(TAG, "🛑 MainActivity destroyed")
        super.onDestroy()
    }
}