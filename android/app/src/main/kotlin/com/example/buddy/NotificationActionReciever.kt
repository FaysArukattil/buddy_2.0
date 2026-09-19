package com.example.buddy

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.app.NotificationCompat
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.*

/**
 * Handles Yes/No button taps on duplicate transaction confirmation notifications.
 *
 * When user taps "Yes, Add":
 *   - Moves the transaction from pending_<hash> to txn_<hash> in SharedPreferences
 *   - Shows a success notification
 *   - Transaction will be synced to Firestore when the user opens the app
 *
 * When user taps "No, Ignore":
 *   - Removes the pending_<hash> entry from SharedPreferences
 */
class NotificationActionReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "NotificationAction"
        private const val PREFS_NAME = "buddy_prefs"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val hash = intent.getStringExtra("hash") ?: return
        val action = intent.action

        Log.d(TAG, "📨 Action received: $action for hash: $hash")

        // Dismiss the notification
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.cancel(hash.hashCode())

        when (action) {
            "ACTION_YES" -> handleYes(context, hash)
            "ACTION_NO" -> handleNo(context, hash)
        }
    }

    private fun handleYes(context: Context, hash: String) {
        Log.d(TAG, "✅ User clicked YES — Adding transaction")

        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val pendingJson = prefs.getString("pending_$hash", null)

        if (pendingJson != null) {
            try {
                val json = JSONObject(pendingJson)

                // Ensure date is in ISO 8601 format
                val dateStr = if (json.has("date")) {
                    json.getString("date")
                } else {
                    SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
                        timeZone = TimeZone.getTimeZone("UTC")
                    }.format(Date())
                }
                json.put("date", dateStr)

                // Move from pending to confirmed
                val success = prefs.edit()
                    .putString("txn_$hash", json.toString())
                    .remove("pending_$hash")
                    .commit()

                if (success) {
                    Log.d(TAG, "✅ Transaction confirmed and saved (will sync on app open)")
                    showSuccessNotification(context, json)
                } else {
                    Log.e(TAG, "❌ Failed to save to SharedPreferences")
                }

            } catch (e: Exception) {
                Log.e(TAG, "❌ Error handling YES: ${e.message}", e)
            }
        } else {
            Log.e(TAG, "❌ No pending transaction found for hash: $hash")
        }
    }

    private fun handleNo(context: Context, hash: String) {
        Log.d(TAG, "❌ User clicked NO — Ignoring transaction")

        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit().remove("pending_$hash").commit()

        Log.d(TAG, "✅ Pending transaction removed")
    }

    private fun showSuccessNotification(context: Context, json: JSONObject) {
        try {
            val amount = json.getDouble("amount")
            val type = json.getString("type")
            val category = json.getString("category")
            val typeIcon = if (type == "expense") "💸" else "💰"

            val channelId = "transaction_added"
            createNotificationChannelIfNeeded(context, channelId)

            val notification = NotificationCompat.Builder(context, channelId)
                .setContentTitle("✅ Transaction Added")
                .setContentText("$typeIcon ₹$amount - $category")
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                .setAutoCancel(true)
                .build()

            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.notify(System.currentTimeMillis().toInt(), notification)

        } catch (e: Exception) {
            Log.e(TAG, "❌ Error showing notification: ${e.message}", e)
        }
    }

    private fun createNotificationChannelIfNeeded(context: Context, channelId: String) {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            val channel = android.app.NotificationChannel(
                channelId,
                "Transaction Added",
                android.app.NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                setShowBadge(false)
            }
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
            manager.createNotificationChannel(channel)
        }
    }
}