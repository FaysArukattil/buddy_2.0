package com.example.buddy

import android.app.*
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import androidx.core.app.NotificationCompat
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.*

class NotificationListener : NotificationListenerService() {

    companion object {
        private const val TAG = "NotificationListener"
        private const val FOREGROUND_NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "notification_listener_channel"
        private const val QUEUE_FILE = "notification_queue.json"
        private const val PREFS_NAME = "buddy_prefs"
        private const val UNSYNCED_TRANSACTIONS_FILE = "unsynced_transactions.json"
        
        // Only SMS/Messaging apps — banks always send SMS for actual transactions
        private val FINANCIAL_APPS = setOf(
            "com.google.android.apps.messaging",
            "com.android.messaging",
            "com.samsung.android.messaging",
            "com.android.mms",
            "com.samsung.android.vvm",
            "com.android.providers.telephony"
        )

        // Apps whose notifications should NEVER be treated as transactions
        private val BLACKLISTED_APPS = setOf(
            "com.whatsapp",
            "com.whatsapp.w4b",
            "org.telegram.messenger",
            "com.instagram.android",
            "com.facebook.orca",
            "com.twitter.android",
            "com.snapchat.android",
            "com.truecaller",
            "com.jio.myjio",
            "com.myairtelapp",
            "com.bsnl.selfcare",
            "com.vi.care"
        )

        // Bill reminder / promotional keywords — reject notifications containing these
        private val BILL_REMINDER_KEYWORDS = listOf(
            "due", "upcoming", "pay by", "bill reminder", "recharge now",
            "plan expiry", "renew", "activate", "your plan", "validity",
            "offer", "cashback offer", "apply now", "click here", "win ",
            "limited time", "download", "subscribe", "free ", "avail ",
            "otp", "verification code", "one time password", "promo",
            "discount", "coupon", "upgrade", "premium plan", "recharge offer",
            "data pack", "missed call", "loan approved", "pre-approved",
            "insurance", "mutual fund", "apply for", "link your",
            "kyc", "pan card", "aadhaar", "verify your", "expire",
            "register", "enroll", "pay your bill", "auto-pay",
            "payment due", "overdue", "outstanding", "reminder"
        )

        // Bank account patterns — strong signal that it's a real bank SMS
        private val ACCOUNT_PATTERN = Regex(
            """(?:a/c|a\.c|acct?|account)\s*[xX*]*\d{2,}""",
            RegexOption.IGNORE_CASE
        )
        private val UPI_REF_PATTERN = Regex(
            """ref\.?\s*\d{6,}""",
            RegexOption.IGNORE_CASE
        )
        private val BALANCE_PATTERN = Regex(
            """(?:bal|balance)[\s:.-]*rs\.?\s*[0-9,]+""",
            RegexOption.IGNORE_CASE
        )
        
        @Volatile
        private var isServiceRunning = false
    }

    private var notificationQueue: MutableList<NotificationData> = mutableListOf()
    private val recentlyProcessed = mutableSetOf<String>()
    private var syncReceiver: BroadcastReceiver? = null

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "🚀 ============ SERVICE CREATED ============")
        
        isServiceRunning = true
        // No WakeLock — NotificationListenerService is kept alive by the OS binding
        loadQueueFromDisk()
        startForegroundService()
        
        // Register broadcast receiver for sync requests
        registerSyncBroadcastReceiver()
        
        // Sync any unsynced transactions when service starts
        syncUnsyncedTransactionsToFlutter()
        
        Log.d(TAG, "✅ Service initialized and running in foreground")
    }

    private fun registerSyncBroadcastReceiver() {
        try {
            syncReceiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context?, intent: Intent?) {
                    Log.d(TAG, "📡 Sync broadcast received")
                    syncUnsyncedTransactionsToFlutter()
                }
            }
            
            val filter = IntentFilter("com.example.buddy.SYNC_UNSYNCED_TRANSACTIONS")
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(syncReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                registerReceiver(syncReceiver, filter)
            }
            
            Log.d(TAG, "✅ Sync broadcast receiver registered")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error registering sync receiver: ${e.message}", e)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "📡 onStartCommand called - Ensuring foreground service")
        
        if (!isServiceRunning) {
            startForegroundService()
            isServiceRunning = true
        }
        
        // Try to sync unsynced transactions
        syncUnsyncedTransactionsToFlutter()
        
        return START_STICKY
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        Log.d(TAG, "✅ ============ LISTENER CONNECTED ============")
        Log.d(TAG, "✅ Now actively monitoring financial app notifications")
        
        isServiceRunning = true
        startForegroundService()
        processQueuedNotifications()
        
        // Sync any pending transactions
        syncUnsyncedTransactionsToFlutter()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return
        
        try {
            // Check if auto-detection is enabled FIRST — skip everything if disabled
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val autoDetectEnabled = prefs.getBoolean("flutter.auto_detect_transactions", true)
            if (!autoDetectEnabled) {
                return  // Silently skip — user has disabled auto-detection
            }

            val pkg = sbn.packageName
            
            if (pkg == applicationContext.packageName) {
                return
            }

            // Check blacklist before doing any work
            if (BLACKLISTED_APPS.contains(pkg)) {
                return
            }
            
            val extras = sbn.notification.extras
            val title = extras.getCharSequence("android.title")?.toString() ?: ""
            val text = extras.getCharSequence("android.text")?.toString() ?: ""
            val bigText = extras.getCharSequence("android.bigText")?.toString() ?: ""
            val content = if (bigText.isNotEmpty()) bigText else text
            
            Log.d(TAG, "📬 NOTIFICATION: $pkg | $title | ${content.take(50)}")
            
            if (!isFromFinancialApp(pkg)) {
                Log.d(TAG, "   ⏭️ Skipping non-financial app")
                return
            }
            
            if (title.isEmpty() && content.isEmpty()) {
                Log.d(TAG, "   ⏭️ Skipping empty notification")
                return
            }
            
            if (isOwnConfirmationNotification(title, content)) {
                Log.d(TAG, "   🚫 Skipping own confirmation notification")
                return
            }
            
            Log.d(TAG, "   ✅ FINANCIAL NOTIFICATION DETECTED!")
            
            processNotificationNatively(pkg, title, content)
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error processing notification: ${e.message}", e)
        }
    }

    private fun isOwnConfirmationNotification(title: String, content: String): Boolean {
        val lower = "$title $content".lowercase()
        return lower.contains("duplicate") ||
               lower.contains("transaction added") ||
               lower.contains("expense tracker") ||
               lower.contains("monitoring financial") ||
               lower.contains("possible duplicate") ||
               lower.contains("similar transaction")
    }

    private fun processNotificationNatively(pkg: String, title: String, content: String) {
        try {
            val fullText = "$title $content"
            val notificationKey = "$pkg|$title|$content"
            
            val timestampedText = "$fullText|${System.currentTimeMillis()}"
            val hash = generateHash(timestampedText)
            
            if (recentlyProcessed.contains(notificationKey)) {
                Log.d(TAG, "   🚫 Already processed recently (same notification)")
                return
            }
            recentlyProcessed.add(notificationKey)
            
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                recentlyProcessed.remove(notificationKey)
            }, 10000)
            
            val transaction = parseTransactionNative(fullText) ?: run {
                Log.d(TAG, "   ⏭️ Could not parse transaction")
                queueNotification(NotificationData(pkg, title, content, System.currentTimeMillis()))
                return
            }
            
            Log.d(TAG, "   💰 Parsed: ₹${transaction.amount} ${transaction.type}")
            
            val similarCount = countSimilarTransactions(transaction.amount, transaction.type)
            
            if (similarCount > 0) {
                Log.d(TAG, "   ⚠️ Found $similarCount similar transaction(s) in last 24 hours")
                storePendingTransaction(hash, transaction, pkg)
                showDuplicateConfirmationNotification(hash, transaction, similarCount)
                Log.d(TAG, "   📬 Waiting for user confirmation...")
                return
            }
            
            if (isDuplicateTransaction(hash)) {
                Log.d(TAG, "   ⚠️ Exact duplicate hash detected - already processed")
                return
            }
            
            Log.d(TAG, "   ✅ No similar transactions - saving directly")
            val saved = saveTransaction(hash, transaction, pkg)
            
            if (saved) {
                // Save to unsynced file for later sync
                saveUnsyncedTransaction(hash, transaction, pkg)
                
                // Try to notify Flutter if app is running
                val flutterNotified = notifyFlutterOfNewTransaction(hash, transaction, pkg)
                
                if (flutterNotified) {
                    Log.d(TAG, "✅ Transaction synced to Flutter immediately")
                } else {
                    Log.d(TAG, "⏳ Transaction saved to unsynced queue - will sync when app opens")
                }
                
                showTransactionAddedNotification(transaction)
            } else {
                Log.e(TAG, "   ❌ Failed to save transaction")
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error in native processing: ${e.message}", e)
        }
    }

    private fun saveUnsyncedTransaction(hash: String, transaction: Transaction, source: String) {
        try {
            val file = File(applicationContext.filesDir, UNSYNCED_TRANSACTIONS_FILE)
            
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
            val isoDate = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
                timeZone = TimeZone.getTimeZone("UTC")
            }.format(Date())
            
            val transactionJson = JSONObject().apply {
                put("hash", hash)
                put("amount", transaction.amount)
                put("type", transaction.type)
                put("category", transaction.category)
                put("icon", transaction.icon)
                put("note", "Auto-detected: ${transaction.note}")
                put("source", source)
                put("timestamp", System.currentTimeMillis())
                put("date", isoDate)
            }
            
            unsyncedArray.put(transactionJson)
            
            // Save back to file
            file.writeText(unsyncedArray.toString())
            
            Log.d(TAG, "💾 Saved to unsynced file (total unsynced: ${unsyncedArray.length()})")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error saving unsynced transaction: ${e.message}", e)
        }
    }

    private fun syncUnsyncedTransactionsToFlutter() {
        try {
            val file = File(applicationContext.filesDir, UNSYNCED_TRANSACTIONS_FILE)
            
            if (!file.exists()) {
                Log.d(TAG, "📭 No unsynced file exists")
                return
            }
            
            if (MainActivity.instance == null) {
                Log.d(TAG, "⏳ MainActivity not available - will sync later")
                return
            }
            
            val unsyncedArray = org.json.JSONArray(file.readText())
            
            if (unsyncedArray.length() == 0) {
                Log.d(TAG, "📭 No unsynced transactions to sync")
                file.delete()
                return
            }
            
            Log.d(TAG, "🔄 Syncing ${unsyncedArray.length()} unsynced transactions to Flutter...")
            
            val syncedHashes = mutableListOf<String>()
            
            for (i in 0 until unsyncedArray.length()) {
                try {
                    val json = unsyncedArray.getJSONObject(i)
                    val hash = json.getString("hash")
                    
                    val transactionData = mapOf(
                        "hash" to hash,
                        "amount" to json.getDouble("amount"),
                        "type" to json.getString("type"),
                        "category" to json.getString("category"),
                        "icon" to json.getInt("icon"),
                        "note" to json.getString("note"),
                        "source" to json.getString("source"),
                        "timestamp" to json.getLong("timestamp"),
                        "date" to json.getString("date")
                    )
                    
                    MainActivity.instance?.saveTransactionToDatabase(transactionData)
                    syncedHashes.add(hash)
                    
                    Log.d(TAG, "   ✅ Synced transaction $hash")
                    
                    // Small delay between syncs to avoid overwhelming Flutter
                    Thread.sleep(100)
                } catch (e: Exception) {
                    Log.e(TAG, "   ❌ Error syncing transaction $i: ${e.message}")
                }
            }
            
            // Remove synced transactions from file
            if (syncedHashes.isNotEmpty()) {
                val remainingArray = org.json.JSONArray()
                for (i in 0 until unsyncedArray.length()) {
                    val json = unsyncedArray.getJSONObject(i)
                    if (!syncedHashes.contains(json.getString("hash"))) {
                        remainingArray.put(json)
                    }
                }
                
                if (remainingArray.length() > 0) {
                    file.writeText(remainingArray.toString())
                } else {
                    file.delete()
                }
                
                Log.d(TAG, "✅ Synced ${syncedHashes.size} transactions. Remaining: ${remainingArray.length()}")
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error syncing unsynced transactions: ${e.message}", e)
        }
    }

    private fun parseTransactionNative(text: String): Transaction? {
        try {
            val lowerText = text.lowercase()

            // ── Step 1: Reject bill reminders / spam / promotional messages ──
            for (keyword in BILL_REMINDER_KEYWORDS) {
                if (lowerText.contains(keyword)) {
                    Log.d(TAG, "   🚫 Rejected: bill reminder/spam keyword '$keyword'")
                    return null
                }
            }

            // ── Step 2: Require banking signals (account number, UPI ref, or balance) ──
            val hasAccount = ACCOUNT_PATTERN.containsMatchIn(text)
            val hasUpiRef = UPI_REF_PATTERN.containsMatchIn(text)
            val hasBalance = BALANCE_PATTERN.containsMatchIn(text)
            if (!hasAccount && !(hasUpiRef && hasBalance)) {
                Log.d(TAG, "   ❌ Rejected: no banking signals (a/c, Ref, Bal) found")
                return null
            }

            // ── Step 3: Determine debit vs credit ──
            val isDebit = when {
                lowerText.contains("paid you") || 
                lowerText.contains("sent you") || 
                lowerText.contains("received from") -> false
                
                lowerText.contains("you paid") || 
                lowerText.contains("you sent") || 
                lowerText.contains("paid to") ||
                lowerText.contains("debited from") ||
                lowerText.contains("withdrawn") -> true
                
                lowerText.contains("credited to") ||
                lowerText.contains("refund") ||
                lowerText.contains("cashback") -> false
                
                lowerText.contains("debited") || 
                lowerText.contains("deducted") -> true
                
                lowerText.contains("credited") || 
                lowerText.contains("deposited") ||
                lowerText.contains("received") -> false
                
                else -> return null
            }
            
            // ── Step 4: Extract amount ──
            val amountPattern = Regex("""(?:Rs\.?\s?|INR\s?|₹\s?)([0-9,]+\.?[0-9]*)|([0-9,]+\.?[0-9]*)\s?(?:Rs\.?|INR|₹)""", RegexOption.IGNORE_CASE)
            val amountMatch = amountPattern.find(text) ?: return null
            
            val amountStr = (amountMatch.groupValues[1].ifEmpty { amountMatch.groupValues[2] })
                .replace(",", "")
                .trim()
            
            val amount = amountStr.toDoubleOrNull() ?: return null
            
            if (amount <= 0) return null
            
            val type = if (isDebit) "expense" else "income"
            val category = detectCategory(lowerText, type)
            val icon = getIconForCategory(category)
            
            Log.d(TAG, "   🔍 Parsed: amount=$amount, type=$type, category=$category")
            
            return Transaction(amount, type, category, icon, text.take(100))
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Parse error: ${e.message}")
            return null
        }
    }

    private fun detectCategory(text: String, type: String): String {
        return if (type == "expense") {
            when {
                text.contains("food") || text.contains("swiggy") || text.contains("zomato") -> "Food"
                text.contains("amazon") || text.contains("flipkart") -> "Shopping"
                text.contains("uber") || text.contains("ola") || text.contains("fuel") -> "Transport"
                text.contains("bill") || text.contains("electricity") -> "Bills"
                text.contains("movie") || text.contains("netflix") -> "Entertainment"
                text.contains("pharmacy") || text.contains("hospital") -> "Health"
                else -> "Other"
            }
        } else {
            when {
                text.contains("salary") -> "Salary"
                text.contains("refund") || text.contains("cashback") -> "Refund"
                text.contains("interest") -> "Interest"
                else -> "Other"
            }
        }
    }

    private fun getIconForCategory(category: String): Int {
        return when (category) {
            "Food" -> 0xe56c
            "Shopping" -> 0xe8cc
            "Transport" -> 0xe531
            "Bills" -> 0xe8b0
            "Entertainment" -> 0xe404
            "Health" -> 0xe3f3
            "Salary" -> 0xe263
            "Refund" -> 0xe5d5
            "Interest" -> 0xe227
            else -> 0xe8f4
        }
    }

    private fun generateHash(text: String): String {
        val digest = MessageDigest.getInstance("SHA-256")
        val hash = digest.digest(text.toByteArray())
        return hash.joinToString("") { "%02x".format(it) }
    }

    private fun isDuplicateTransaction(hash: String): Boolean {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.contains("txn_$hash")
    }

    private fun countSimilarTransactions(amount: Double, type: String): Int {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val now = System.currentTimeMillis()
        val oneDayAgo = now - (24 * 60 * 60 * 1000)
        
        var count = 0
        val allPrefs = prefs.all
        
        for ((key, value) in allPrefs) {
            if (key.startsWith("txn_") || key.startsWith("pending_")) {
                try {
                    val json = JSONObject(value as String)
                    val txnAmount = json.getDouble("amount")
                    val txnType = json.getString("type")
                    val txnTime = json.getLong("timestamp")
                    
                    if (txnAmount == amount && txnType == type && txnTime >= oneDayAgo) {
                        count++
                    }
                } catch (e: Exception) {
                    // Skip invalid entries
                }
            }
        }
        
        return count
    }

    private fun saveTransaction(hash: String, transaction: Transaction, source: String): Boolean {
        return try {
            val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val json = JSONObject().apply {
                put("amount", transaction.amount)
                put("type", transaction.type)
                put("category", transaction.category)
                put("icon", transaction.icon)
                put("note", "Auto-detected: ${transaction.note}")
                put("source", source)
                put("timestamp", System.currentTimeMillis())
                put("date", SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US).format(Date()))
            }
            
            val success = prefs.edit().putString("txn_$hash", json.toString()).commit()
            
            if (success) {
                Log.d(TAG, "💾 Transaction saved to SharedPreferences: $hash")
            } else {
                Log.e(TAG, "❌ Failed to save to SharedPreferences")
            }
            
            success
        } catch (e: Exception) {
            Log.e(TAG, "❌ Exception saving transaction: ${e.message}", e)
            false
        }
    }

    private fun storePendingTransaction(hash: String, transaction: Transaction, source: String) {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val json = JSONObject().apply {
            put("amount", transaction.amount)
            put("type", transaction.type)
            put("category", transaction.category)
            put("icon", transaction.icon)
            put("note", "Auto-detected: ${transaction.note}")
            put("source", source)
            put("timestamp", System.currentTimeMillis())
        }
        
        prefs.edit().putString("pending_$hash", json.toString()).apply()
        Log.d(TAG, "💾 Pending transaction stored: $hash")
    }

    private fun notifyFlutterOfNewTransaction(hash: String, transaction: Transaction, source: String): Boolean {
        Log.d(TAG, "📤 Attempting to notify Flutter of new transaction: $hash")
        
        return try {
            if (MainActivity.instance == null) {
                Log.d(TAG, "⚠️ MainActivity not available - transaction will sync later")
                return false
            }
            
            val isoDate = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
                timeZone = TimeZone.getTimeZone("UTC")
            }.format(Date())
            
            val transactionData = mapOf(
                "hash" to hash,
                "amount" to transaction.amount,
                "type" to transaction.type,
                "category" to transaction.category,
                "icon" to transaction.icon,
                "note" to "Auto-detected: ${transaction.note}",
                "source" to source,
                "timestamp" to System.currentTimeMillis(),
                "date" to isoDate
            )
            
            MainActivity.instance?.saveTransactionToDatabase(transactionData)
            
            Log.d(TAG, "✅ Flutter notified successfully")
            true
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error notifying Flutter: ${e.message}", e)
            false
        }
    }

    private fun showDuplicateConfirmationNotification(hash: String, transaction: Transaction, similarCount: Int) {
        val channelId = "duplicate_confirmations"
        createNotificationChannel(channelId, "Transaction Confirmations", NotificationManager.IMPORTANCE_HIGH)
        
        val typeIcon = if (transaction.type == "expense") "💸" else "💰"
        
        val yesIntent = Intent(this, NotificationActionReceiver::class.java).apply {
            action = "ACTION_YES"
            putExtra("hash", hash)
        }
        val yesPendingIntent = PendingIntent.getBroadcast(
            this, 
            hash.hashCode(), 
            yesIntent, 
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        val noIntent = Intent(this, NotificationActionReceiver::class.java).apply {
            action = "ACTION_NO"
            putExtra("hash", hash)
        }
        val noPendingIntent = PendingIntent.getBroadcast(
            this, 
            hash.hashCode() + 1, 
            noIntent, 
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        val notification = NotificationCompat.Builder(this, channelId)
            .setContentTitle("⚠️ Possible Duplicate Transaction")
            .setContentText("$typeIcon ₹${transaction.amount} (${transaction.category})")
            .setStyle(NotificationCompat.BigTextStyle()
                .bigText("$typeIcon ₹${transaction.amount} - ${transaction.category}\n\nFound $similarCount similar transaction(s) in last 24 hours.\n\nIs this a NEW transaction?"))
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(false)
            .addAction(android.R.drawable.ic_input_add, "✅ Yes, Add", yesPendingIntent)
            .addAction(android.R.drawable.ic_delete, "❌ No, Ignore", noPendingIntent)
            .build()
        
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(hash.hashCode(), notification)
        
        Log.d(TAG, "🔔 Duplicate confirmation notification shown")
    }

    private fun showTransactionAddedNotification(transaction: Transaction) {
        val channelId = "transaction_added"
        createNotificationChannel(channelId, "Transactions Added", NotificationManager.IMPORTANCE_DEFAULT)
        
        val typeIcon = if (transaction.type == "expense") "💸" else "💰"
        
        val notification = NotificationCompat.Builder(this, channelId)
            .setContentTitle("✅ Transaction Added")
            .setContentText("$typeIcon ₹${transaction.amount} - ${transaction.category}")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setAutoCancel(true)
            .build()
        
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(System.currentTimeMillis().toInt(), notification)
        
        Log.d(TAG, "🔔 Transaction added notification shown")
    }

    private fun isFromFinancialApp(packageName: String): Boolean {
        if (BLACKLISTED_APPS.contains(packageName)) return false
        if (FINANCIAL_APPS.contains(packageName)) return true
        
        val lower = packageName.lowercase()
        // Only match SMS/messaging apps — banks send SMS for real transactions
        val smsKeywords = listOf("sms", "message", "messaging", "mms")
        
        return smsKeywords.any { lower.contains(it) }
    }

    private fun queueNotification(data: NotificationData) {
        notificationQueue.add(data)
        saveQueueToDisk()
        Log.d(TAG, "💾 Queued notification (total: ${notificationQueue.size})")
    }

    private fun processQueuedNotifications() {
        if (notificationQueue.isEmpty()) {
            Log.d(TAG, "📭 No queued notifications")
            return
        }
        
        Log.d(TAG, "📮 Processing ${notificationQueue.size} queued notifications")
        
        val activity = MainActivity.instance
        if (activity != null) {
            val toProcess = notificationQueue.toList()
            
            activity.runOnUiThread {
                for (data in toProcess) {
                    try {
                        activity.sendNotificationToFlutter(data.packageName, data.title, data.content)
                        notificationQueue.remove(data)
                    } catch (e: Exception) {
                        Log.e(TAG, "❌ Error processing queued: ${e.message}")
                    }
                }
                saveQueueToDisk()
            }
        }
    }

    private fun saveQueueToDisk() {
        try {
            val file = File(applicationContext.filesDir, QUEUE_FILE)
            val jsonArray = org.json.JSONArray()
            
            for (data in notificationQueue) {
                val json = JSONObject().apply {
                    put("packageName", data.packageName)
                    put("title", data.title)
                    put("content", data.content)
                    put("timestamp", data.timestamp)
                }
                jsonArray.put(json)
            }
            
            file.writeText(jsonArray.toString())
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error saving queue: ${e.message}", e)
        }
    }

    private fun loadQueueFromDisk() {
        try {
            val file = File(applicationContext.filesDir, QUEUE_FILE)
            if (!file.exists()) return
            
            val jsonArray = org.json.JSONArray(file.readText())
            notificationQueue.clear()
            
            for (i in 0 until jsonArray.length()) {
                val json = jsonArray.getJSONObject(i)
                val data = NotificationData(
                    json.getString("packageName"),
                    json.getString("title"),
                    json.getString("content"),
                    json.getLong("timestamp")
                )
                notificationQueue.add(data)
            }
            
            Log.d(TAG, "📂 Loaded ${notificationQueue.size} notifications")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error loading queue: ${e.message}", e)
        }
    }

    // WakeLock removed — NotificationListenerService is kept alive by the OS
    // binding. The WakeLock was causing unnecessary battery drain.

    private fun startForegroundService() {
        createNotificationChannel(CHANNEL_ID, "Transaction Monitor", NotificationManager.IMPORTANCE_LOW)
        
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE
        )
        
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Expense Tracker Active")
            .setContentText("Monitoring financial notifications")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            .build()
        
        startForeground(FOREGROUND_NOTIFICATION_ID, notification)
    }

    private fun createNotificationChannel(channelId: String, channelName: String, importance: Int) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(channelId, channelName, importance).apply {
                setShowBadge(false)
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        Log.e(TAG, "❌ LISTENER DISCONNECTED")
        isServiceRunning = false
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            requestRebind(android.content.ComponentName(this, NotificationListener::class.java))
        }
    }

    override fun onDestroy() {
        Log.d(TAG, "🛑 SERVICE DESTROYED")
        isServiceRunning = false
        saveQueueToDisk()
        
        // Unregister sync receiver
        try {
            syncReceiver?.let { unregisterReceiver(it) }
            Log.d(TAG, "✅ Sync receiver unregistered")
        } catch (e: Exception) {
            Log.e(TAG, "⚠️ Error unregistering sync receiver: ${e.message}")
        }
        
        super.onDestroy()
        // No self-restart — START_STICKY + OS notification listener rebinding handles this.
        // The manual restart was causing a restart storm and draining battery.
    }

    data class NotificationData(
        val packageName: String,
        val title: String,
        val content: String,
        val timestamp: Long
    )
    
    data class Transaction(
        val amount: Double,
        val type: String,
        val category: String,
        val icon: Int,
        val note: String
    )
}