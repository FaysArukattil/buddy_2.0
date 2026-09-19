package com.faysarukattil.buddy

import android.content.Context
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import org.json.JSONObject
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.*

/**
 * Lightweight NotificationListenerService that processes bank SMS notifications.
 *
 * Architecture:
 * - The OS keeps this service alive via the notification listener binding.
 *   NO foreground service, NO START_STICKY, NO WakeLock needed.
 * - When a notification arrives: filter → parse → save to SharedPreferences → done.
 * - When the user opens the app, Flutter reads SharedPreferences and syncs to Firestore.
 *
 * This design ensures near-zero CPU usage when idle.
 */
class NotificationListener : NotificationListenerService() {

    companion object {
        private const val TAG = "NotificationListener"
        private const val PREFS_NAME = "FlutterSharedPreferences"
        private const val KEY_PREFIX = "flutter."

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
        private val SPAM_KEYWORDS = listOf(
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
        private val AMOUNT_PATTERN = Regex(
            """(?:Rs\.?\s?|INR\s?|₹\s?)([0-9,]+\.?[0-9]*)|([0-9,]+\.?[0-9]*)\s?(?:Rs\.?|INR|₹)""",
            RegexOption.IGNORE_CASE
        )
    }

    // Simple LRU-style dedup: keeps last 50 notification keys.
    // No Handler timers — entries are evicted by insertion order.
    private val recentlyProcessed = LinkedHashSet<String>()
    private val maxRecentSize = 50

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "✅ NotificationListener created (OS-managed)")
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        Log.d(TAG, "✅ Listener connected — monitoring SMS notifications")
        migrateOldPrefs()
    }

    /**
     * One-time migration: copy txn_/pending_ entries from the old "buddy_prefs"
     * file to "FlutterSharedPreferences" with the "flutter." prefix so Flutter
     * can read them. This handles any transactions that were saved before the fix.
     */
    private fun migrateOldPrefs() {
        try {
            val oldPrefs = getSharedPreferences("buddy_prefs", Context.MODE_PRIVATE)
            val oldAll = oldPrefs.all
            if (oldAll.isEmpty()) return

            val newPrefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val editor = newPrefs.edit()
            var migrated = 0

            for ((key, value) in oldAll) {
                if ((key.startsWith("txn_") || key.startsWith("pending_")) && value is String) {
                    val newKey = "${KEY_PREFIX}$key"
                    if (!newPrefs.contains(newKey)) {
                        editor.putString(newKey, value)
                        migrated++
                    }
                }
            }

            if (migrated > 0) {
                editor.apply()
                // Clear old prefs after migration
                oldPrefs.edit().clear().apply()
                Log.d(TAG, "✅ Migrated $migrated transaction(s) from old prefs to FlutterSharedPreferences")
            }
        } catch (e: Exception) {
            Log.e(TAG, "⚠️ Migration error (non-critical): ${e.message}")
        }
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        // Let the OS handle rebinding. Do NOT call requestRebind() —
        // it causes aggressive reconnection loops and battery drain.
        Log.d(TAG, "⚠️ Listener disconnected — OS will rebind automatically")
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return

        try {
            // 1. Check if auto-detection is enabled
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val autoDetectEnabled = prefs.getBoolean("flutter.auto_detect_transactions", true)
            if (!autoDetectEnabled) return

            val pkg = sbn.packageName

            // 2. Skip own notifications and blacklisted apps
            if (pkg == applicationContext.packageName) return
            if (BLACKLISTED_APPS.contains(pkg)) return

            // 3. Only process SMS/messaging apps
            if (!isFromFinancialApp(pkg)) return

            // 4. Extract notification text
            val extras = sbn.notification.extras
            val title = extras.getCharSequence("android.title")?.toString() ?: ""
            val text = extras.getCharSequence("android.text")?.toString() ?: ""
            val bigText = extras.getCharSequence("android.bigText")?.toString() ?: ""
            val content = if (bigText.isNotEmpty()) bigText else text

            if (title.isEmpty() && content.isEmpty()) return

            // 5. Skip own confirmation notifications
            if (isOwnNotification(title, content)) return

            // 6. Dedup: skip if we've seen this exact notification recently
            val notificationKey = "$pkg|$title|$content"
            synchronized(recentlyProcessed) {
                if (recentlyProcessed.contains(notificationKey)) return
                recentlyProcessed.add(notificationKey)
                // Evict oldest entries if over limit
                while (recentlyProcessed.size > maxRecentSize) {
                    val first = recentlyProcessed.iterator().next()
                    recentlyProcessed.remove(first)
                }
            }

            // 7. Parse transaction
            val fullText = "$title $content"
            val transaction = parseTransaction(fullText) ?: return

            Log.d(TAG, "💰 Transaction detected: ₹${transaction.amount} ${transaction.type} (${transaction.category})")

            // 8. Generate hash and check for duplicates
            val hash = generateHash("$fullText|${System.currentTimeMillis()}")

            val buddyPrefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            if (buddyPrefs.contains("${KEY_PREFIX}txn_$hash")) {
                Log.d(TAG, "⚠️ Duplicate hash — skipping")
                return
            }

            // 9. Check for similar transactions (same amount + type in last 24h)
            val similarCount = countSimilarTransactions(buddyPrefs, transaction.amount, transaction.type)

            if (similarCount > 0) {
                // Store as pending and show confirmation notification
                storePendingTransaction(buddyPrefs, hash, transaction, pkg)
                showDuplicateConfirmationNotification(hash, transaction, similarCount)
                Log.d(TAG, "⚠️ $similarCount similar transaction(s) found — asking user to confirm")
                return
            }

            // 10. Save transaction directly
            saveTransaction(buddyPrefs, hash, transaction, pkg)
            showTransactionAddedNotification(transaction)

            Log.d(TAG, "✅ Transaction saved to SharedPreferences (hash=$hash)")

        } catch (e: Exception) {
            Log.e(TAG, "❌ Error processing notification: ${e.message}", e)
        }
    }

    // ── Filtering ──

    private fun isFromFinancialApp(packageName: String): Boolean {
        if (FINANCIAL_APPS.contains(packageName)) return true
        val lower = packageName.lowercase()
        return listOf("sms", "message", "messaging", "mms").any { lower.contains(it) }
    }

    private fun isOwnNotification(title: String, content: String): Boolean {
        val lower = "$title $content".lowercase()
        return lower.contains("duplicate") ||
               lower.contains("transaction added") ||
               lower.contains("expense tracker") ||
               lower.contains("monitoring financial") ||
               lower.contains("possible duplicate") ||
               lower.contains("similar transaction")
    }

    // ── Parsing ──

    private fun parseTransaction(text: String): Transaction? {
        val lowerText = text.lowercase()

        // Step 1: Reject spam/promotional messages
        for (keyword in SPAM_KEYWORDS) {
            if (lowerText.contains(keyword)) return null
        }

        // Step 2: Require banking signals (account number, UPI ref, or balance)
        val hasAccount = ACCOUNT_PATTERN.containsMatchIn(text)
        val hasUpiRef = UPI_REF_PATTERN.containsMatchIn(text)
        val hasBalance = BALANCE_PATTERN.containsMatchIn(text)
        if (!hasAccount && !(hasUpiRef && hasBalance)) return null

        // Step 3: Determine debit vs credit
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

        // Step 4: Extract amount
        val amountMatch = AMOUNT_PATTERN.find(text) ?: return null
        val amountStr = (amountMatch.groupValues[1].ifEmpty { amountMatch.groupValues[2] })
            .replace(",", "")
            .trim()
        val amount = amountStr.toDoubleOrNull() ?: return null
        if (amount <= 0) return null

        val type = if (isDebit) "expense" else "income"
        val category = detectCategory(lowerText, type)
        val icon = getIconForCategory(category)

        return Transaction(amount, type, category, icon, text.take(100))
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

    // ── Storage ──

    private fun generateHash(text: String): String {
        val digest = MessageDigest.getInstance("SHA-256")
        val hash = digest.digest(text.toByteArray())
        return hash.joinToString("") { "%02x".format(it) }
    }

    private fun countSimilarTransactions(prefs: android.content.SharedPreferences, amount: Double, type: String): Int {
        val oneDayAgo = System.currentTimeMillis() - (24 * 60 * 60 * 1000)
        var count = 0

        for ((key, value) in prefs.all) {
            if (key.startsWith("${KEY_PREFIX}txn_") || key.startsWith("${KEY_PREFIX}pending_")) {
                try {
                    val json = JSONObject(value as String)
                    val txnAmount = json.getDouble("amount")
                    val txnType = json.getString("type")
                    val txnTime = json.getLong("timestamp")

                    if (txnAmount == amount && txnType == type && txnTime >= oneDayAgo) {
                        count++
                    }
                } catch (_: Exception) {
                    // Skip invalid entries
                }
            }
        }

        return count
    }

    private fun saveTransaction(prefs: android.content.SharedPreferences, hash: String, transaction: Transaction, source: String) {
        val isoDate = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }.format(Date())

        val json = JSONObject().apply {
            put("amount", transaction.amount)
            put("type", transaction.type)
            put("category", transaction.category)
            put("icon", transaction.icon)
            put("note", "Auto-detected: ${transaction.note}")
            put("source", source)
            put("timestamp", System.currentTimeMillis())
            put("date", isoDate)
        }

        prefs.edit().putString("${KEY_PREFIX}txn_$hash", json.toString()).apply()
    }

    private fun storePendingTransaction(prefs: android.content.SharedPreferences, hash: String, transaction: Transaction, source: String) {
        val isoDate = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }.format(Date())

        val json = JSONObject().apply {
            put("amount", transaction.amount)
            put("type", transaction.type)
            put("category", transaction.category)
            put("icon", transaction.icon)
            put("note", "Auto-detected: ${transaction.note}")
            put("source", source)
            put("timestamp", System.currentTimeMillis())
            put("date", isoDate)
        }

        prefs.edit().putString("${KEY_PREFIX}pending_$hash", json.toString()).apply()
    }

    // ── Notifications ──

    private fun showDuplicateConfirmationNotification(hash: String, transaction: Transaction, similarCount: Int) {
        val channelId = "duplicate_confirmations"
        createNotificationChannel(channelId, "Transaction Confirmations", android.app.NotificationManager.IMPORTANCE_HIGH)

        val typeIcon = if (transaction.type == "expense") "💸" else "💰"

        val yesIntent = android.content.Intent(this, NotificationActionReceiver::class.java).apply {
            action = "ACTION_YES"
            putExtra("hash", hash)
        }
        val yesPendingIntent = android.app.PendingIntent.getBroadcast(
            this,
            hash.hashCode(),
            yesIntent,
            android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
        )

        val noIntent = android.content.Intent(this, NotificationActionReceiver::class.java).apply {
            action = "ACTION_NO"
            putExtra("hash", hash)
        }
        val noPendingIntent = android.app.PendingIntent.getBroadcast(
            this,
            hash.hashCode() + 1,
            noIntent,
            android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
        )

        val notification = androidx.core.app.NotificationCompat.Builder(this, channelId)
            .setContentTitle("⚠️ Possible Duplicate Transaction")
            .setContentText("$typeIcon ₹${transaction.amount} (${transaction.category})")
            .setStyle(androidx.core.app.NotificationCompat.BigTextStyle()
                .bigText("$typeIcon ₹${transaction.amount} - ${transaction.category}\n\nFound $similarCount similar transaction(s) in last 24 hours.\n\nIs this a NEW transaction?"))
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setPriority(androidx.core.app.NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(false)
            .addAction(android.R.drawable.ic_input_add, "✅ Yes, Add", yesPendingIntent)
            .addAction(android.R.drawable.ic_delete, "❌ No, Ignore", noPendingIntent)
            .build()

        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
        notificationManager.notify(hash.hashCode(), notification)
    }

    private fun showTransactionAddedNotification(transaction: Transaction) {
        val channelId = "transaction_added"
        createNotificationChannel(channelId, "Transactions Added", android.app.NotificationManager.IMPORTANCE_DEFAULT)

        val typeIcon = if (transaction.type == "expense") "💸" else "💰"

        val notification = androidx.core.app.NotificationCompat.Builder(this, channelId)
            .setContentTitle("✅ Transaction Added")
            .setContentText("$typeIcon ₹${transaction.amount} - ${transaction.category}")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setPriority(androidx.core.app.NotificationCompat.PRIORITY_DEFAULT)
            .setAutoCancel(true)
            .build()

        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
        notificationManager.notify(System.currentTimeMillis().toInt(), notification)
    }

    private fun createNotificationChannel(channelId: String, channelName: String, importance: Int) {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            val channel = android.app.NotificationChannel(channelId, channelName, importance).apply {
                setShowBadge(false)
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    override fun onDestroy() {
        Log.d(TAG, "🛑 NotificationListener destroyed")
        super.onDestroy()
    }

    data class Transaction(
        val amount: Double,
        val type: String,
        val category: String,
        val icon: Int,
        val note: String
    )
}