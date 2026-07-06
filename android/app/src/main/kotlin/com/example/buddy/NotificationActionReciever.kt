package com.example.buddy

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.app.NotificationCompat
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.*

class NotificationActionReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "NotificationAction"
        private const val PREFS_NAME = "buddy_prefs"
        private const val UNSYNCED_TRANSACTIONS_FILE = "unsynced_transactions.json"
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
        Log.d(TAG, "✅ User clicked YES - Adding transaction")
        
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
                
                // 1. Save as confirmed transaction in SharedPreferences
                val saveSuccess = prefs.edit()
                    .putString("txn_$hash", json.toString())
                    .remove("pending_$hash")
                    .commit()
                
                if (!saveSuccess) {
                    Log.e(TAG, "❌ Failed to save to SharedPreferences")
                    return
                }
                
                Log.d(TAG, "✅ Transaction moved from pending to confirmed in SharedPreferences")
                
                // 2. CRITICAL: Save to unsynced file for Flutter sync when app opens
                saveToUnsyncedFile(context, hash, json, dateStr)
                
                // 3. Try to notify Flutter if app is running
                val mainActivity = MainActivity.instance
                if (mainActivity != null) {
                    Log.d(TAG, "📤 MainActivity is AVAILABLE - syncing immediately")
                    
                    val transactionData = mapOf(
                        "hash" to hash,
                        "amount" to json.getDouble("amount"),
                        "type" to json.getString("type"),
                        "category" to json.getString("category"),
                        "icon" to json.getInt("icon"),
                        "note" to json.optString("note", "Auto-detected from notification"),
                        "source" to json.optString("source", "unknown"),
                        "timestamp" to json.optLong("timestamp", System.currentTimeMillis()),
                        "date" to dateStr
                    )
                    
                    mainActivity.saveTransactionToDatabase(transactionData)
                    mainActivity.handleDuplicateResponse(hash, true)
                    
                    Log.d(TAG, "✅ Transaction synced to Flutter immediately")
                } else {
                    Log.d(TAG, "⏳ MainActivity is NULL - transaction saved to unsynced file")
                    Log.d(TAG, "   Will sync when app opens")
                }
                
                // 4. Show success notification
                showSuccessNotification(context, json)
                
            } catch (e: Exception) {
                Log.e(TAG, "❌ Error handling YES: ${e.message}", e)
                e.printStackTrace()
            }
        } else {
            Log.e(TAG, "❌ No pending transaction found for hash: $hash")
        }
    }

    private fun saveToUnsyncedFile(context: Context, hash: String, json: JSONObject, dateStr: String) {
        try {
            val file = File(context.filesDir, UNSYNCED_TRANSACTIONS_FILE)
            
            // Load existing unsynced transactions
            val unsyncedArray = if (file.exists()) {
                org.json.JSONArray(file.readText())
            } else {
                org.json.JSONArray()
            }
            
            // Check if already exists
            for (i in 0 until unsyncedArray.length()) {
                val existing = unsyncedArray.getJSONObject(i)
                if (existing.getString("hash") == hash) {
                    Log.d(TAG, "⚠️ Transaction already in unsynced file - skipping")
                    return
                }
            }
            
            // Add new transaction
            val transactionJson = JSONObject().apply {
                put("hash", hash)
                put("amount", json.getDouble("amount"))
                put("type", json.getString("type"))
                put("category", json.getString("category"))
                put("icon", json.getInt("icon"))
                put("note", json.optString("note", "Auto-detected from notification"))
                put("source", json.optString("source", "unknown"))
                put("timestamp", json.optLong("timestamp", System.currentTimeMillis()))
                put("date", dateStr)
            }
            
            unsyncedArray.put(transactionJson)
            
            // Save back to file
            file.writeText(unsyncedArray.toString())
            
            Log.d(TAG, "💾 Saved to unsynced file (total unsynced: ${unsyncedArray.length()})")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error saving to unsynced file: ${e.message}", e)
            e.printStackTrace()
        }
    }

    private fun handleNo(context: Context, hash: String) {
        Log.d(TAG, "❌ User clicked NO - Ignoring transaction")
        
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val removed = prefs.edit().remove("pending_$hash").commit()
        
        if (removed) {
            Log.d(TAG, "✅ Pending transaction removed")
        } else {
            Log.e(TAG, "⚠️ Failed to remove pending transaction")
        }
        
        // Try to notify Flutter if running
        MainActivity.instance?.handleDuplicateResponse(hash, false)
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
            
            Log.d(TAG, "🔔 Success notification shown")
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