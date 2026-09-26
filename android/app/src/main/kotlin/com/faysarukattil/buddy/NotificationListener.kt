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

        // SMS/Messaging apps — banks always send SMS for actual transactions
        // Also includes UPI payment apps that send transaction notifications
        private val FINANCIAL_APPS = setOf(
            // SMS / Messaging (including OEM packages for Nothing, Vivo, Xiaomi, Oppo, Samsung, OnePlus, etc.)
            "com.google.android.apps.messaging",
            "com.android.messaging",
            "com.samsung.android.messaging",
            "com.android.mms",
            "com.samsung.android.vvm",
            "com.android.providers.telephony",
            "com.nothing.messaging",
            "com.oneplus.mms",
            "com.bbm.messaging",
            "com.vivo.mms",
            "com.coloros.mms",
            "com.miui.mms",
            "com.oppo.mms",
            "com.motorola.mms",
            "com.transsion.mobile.message",
            // UPI / Payment apps (they send transaction confirmations)
            "com.phonepe.app",
            "com.google.android.apps.nbu.paisa.user",  // GPay
            "net.one97.paytm",
            "in.org.npci.upiapp",  // BHIM UPI
            "com.dreamplug.androidapp",  // CRED
            "com.mobikwik_new",
            "com.freecharge.android",
            // Bank apps
            "com.sbi.SBIFreedomPlus",
            "com.csam.icici.bank.imobile",
            "com.hdfc.retail",
            "com.axis.mobile",
            "com.msf.kbank.mobile",
            "com.kotak.mobile.banking",
            "com.bankofbaroda.mconnect",
            "com.canaaborbank.mobility",
            "com.fedmobile",  // Federal Bank
            "com.idfcfirst.bank"
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
            "com.vi.care",
            "com.google.android.youtube",
            "com.spotify.music",
            "com.netflix.mediaclient"
        )

        // Spam/promotional keywords — reject notifications containing these
        // NOTE: "refund" and "cashback" are NOT spam — they're valid credit transactions
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

        // Keywords that indicate an ACTUAL financial transaction — these override spam filter
        private val TRANSACTION_SIGNAL_KEYWORDS = listOf(
            "debited", "credited", "deducted", "deposited", "received",
            "withdrawn", "transferred", "sent to", "paid to",
            "refund", "cashback", "reversed"
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
            """(?:bal|balance)[\s:.-]*(?:rs\.?\s?|inr\s?|₹\s?)?[0-9,]+""",
            RegexOption.IGNORE_CASE
        )
        private val AMOUNT_PATTERN = Regex(
            """(?:Rs\.?\s?|INR\s?|₹\s?)([0-9,]+\.?[0-9]*)|([0-9,]+\.?[0-9]*)\s?(?:Rs\.?|INR|₹)""",
            RegexOption.IGNORE_CASE
        )

        // ── Merchant → Category mapping (all lowercase for matching) ──
        // Category names match the app's default categories in FirestoreService:
        // 'Swiggy', 'Zomato', 'Zepto', 'Instamart', 'Amazon', 'Flipkart', 'Myntra',
        // 'Transport', 'Uber', 'Ola', 'Rapido', 'Fuel', 'Netflix', 'YouTube', 'Spotify',
        // 'Hotstar', 'Gym & Fitness', 'Medical', 'Education', 'Rent', 'Bills & Utilities',
        // 'Recharge', 'Coffee', 'Travel', 'Party', 'Gifts & Charity', 'Subscriptions',
        // 'Local Food', 'Jio Internet', 'WiFi', 'Other'
        // Income categories:
        // 'Salary', 'Freelance', 'Business', 'Investment', 'Interest', 'Refund',
        // 'Gift', 'Cashback', 'Rental Income', 'Other'
        private val MERCHANT_CATEGORY_MAP: Map<String, Pair<String, Int>> = mapOf(
            // Food delivery & quick commerce
            "zomato" to Pair("Zomato", 63286),
            "swiggy" to Pair("Swiggy", 63129),
            "zepto" to Pair("Zepto", 62922),
            "instamart" to Pair("Instamart", 983521),
            "blinkit" to Pair("Zepto", 62922),
            "bigbasket" to Pair("Instamart", 983521),
            "dunzo" to Pair("Zepto", 62922),

            // Shopping & E-commerce
            "amazon" to Pair("Amazon", 63522),
            "flipkart" to Pair("Flipkart", 983407),
            "myntra" to Pair("Myntra", 63033),
            "ajio" to Pair("Myntra", 63033),
            "meesho" to Pair("Flipkart", 983407),
            "nykaa" to Pair("Myntra", 63033),
            "snapdeal" to Pair("Flipkart", 983407),
            "croma" to Pair("Flipkart", 983407),
            "reliance" to Pair("Amazon", 63522),
            "decathlon" to Pair("Amazon", 63522),

            // Rides & Transport & Fuel
            "uber" to Pair("Uber", 63616),
            "ola" to Pair("Ola", 63616),
            "rapido" to Pair("Rapido", 983646),
            "namma yatri" to Pair("Uber", 63616),
            "fuel" to Pair("Fuel", 63597),
            "petrol" to Pair("Fuel", 63597),
            "diesel" to Pair("Fuel", 63597),
            "indian oil" to Pair("Fuel", 63597),
            "hp petrol" to Pair("Fuel", 63597),
            "bharat petroleum" to Pair("Fuel", 63597),
            "shell" to Pair("Fuel", 63597),
            "metro" to Pair("Transport", 63155),
            "irctc" to Pair("Travel", 63346),
            "redbus" to Pair("Travel", 63346),

            // Entertainment & Streaming
            "netflix" to Pair("Netflix", 983645),
            "youtube" to Pair("YouTube", 983086),
            "spotify" to Pair("Spotify", 63725),
            "hotstar" to Pair("Hotstar", 63584),
            "disney" to Pair("Hotstar", 63584),
            "prime video" to Pair("Netflix", 983645),
            "jio cinema" to Pair("Hotstar", 63584),
            "sonyliv" to Pair("Hotstar", 63584),
            "zee5" to Pair("Hotstar", 63584),
            "bookmyshow" to Pair("Hotstar", 63584),
            "pvr" to Pair("Hotstar", 63584),
            "inox" to Pair("Hotstar", 63584),

            // Bills, Utilities & Recharge
            "jio fiber" to Pair("Jio Internet", 983319),
            "jiofiber" to Pair("Jio Internet", 983319),
            "airtel" to Pair("Recharge", 983160),
            "jio" to Pair("Recharge", 983160),
            "vodafone" to Pair("Recharge", 983160),
            "vi " to Pair("Recharge", 983160),
            "bsnl" to Pair("Recharge", 983160),
            "recharge" to Pair("Recharge", 983160),
            "wifi" to Pair("WiFi", 983743),
            "broadband" to Pair("WiFi", 983743),
            "act fibernet" to Pair("WiFi", 983743),
            "electricity" to Pair("Bills & Utilities", 983265),
            "water bill" to Pair("Bills & Utilities", 983265),
            "gas bill" to Pair("Bills & Utilities", 983265),
            "bill" to Pair("Bills & Utilities", 983265),

            // Food & Cafes
            "coffee" to Pair("Coffee", 63061),
            "starbucks" to Pair("Coffee", 63061),
            "cafe" to Pair("Coffee", 63061),
            "domino" to Pair("Local Food", 63609),
            "pizza hut" to Pair("Local Food", 63609),
            "mcdonald" to Pair("Local Food", 63609),
            "kfc" to Pair("Local Food", 63609),
            "burger king" to Pair("Local Food", 63609),
            "subway" to Pair("Local Food", 63609),
            "restaurant" to Pair("Local Food", 63609),
            "bakery" to Pair("Local Food", 63609),
            "food" to Pair("Local Food", 63609),

            // Health & Medical
            "pharmacy" to Pair("Medical", 63664),
            "hospital" to Pair("Medical", 63664),
            "medical" to Pair("Medical", 63664),
            "apollo" to Pair("Medical", 63664),
            "1mg" to Pair("Medical", 63664),
            "pharmeasy" to Pair("Medical", 63664),
            "netmeds" to Pair("Medical", 63664),
            "practo" to Pair("Medical", 63664),

            // Fitness
            "gym" to Pair("Gym & Fitness", 63335),
            "fitness" to Pair("Gym & Fitness", 63335),
            "cult.fit" to Pair("Gym & Fitness", 63335),
            "cult fit" to Pair("Gym & Fitness", 63335),

            // Education
            "udemy" to Pair("Education", 983342),
            "coursera" to Pair("Education", 983342),
            "unacademy" to Pair("Education", 983342),
            "byju" to Pair("Education", 983342),
            "school" to Pair("Education", 983342),
            "college" to Pair("Education", 983342),
            "tuition" to Pair("Education", 983342),
            "education" to Pair("Education", 983342),

            // Travel & Stay
            "flight" to Pair("Travel", 63346),
            "makemytrip" to Pair("Travel", 63346),
            "goibibo" to Pair("Travel", 63346),
            "cleartrip" to Pair("Travel", 63346),
            "indigo" to Pair("Travel", 63346),
            "air india" to Pair("Travel", 63346),
            "travel" to Pair("Travel", 63346),

            // Lifestyle / Housing
            "rent" to Pair("Rent", 63477),
            "party" to Pair("Party", 63013),
            "club" to Pair("Party", 63013),
            "pub" to Pair("Party", 63013),
            "charity" to Pair("Gifts & Charity", 983707),
            "donation" to Pair("Gifts & Charity", 983707),
            "subscription" to Pair("Subscriptions", 62878),

            // Income signals
            "salary" to Pair("Salary", 983128),
            "payroll" to Pair("Salary", 983128),
            "stipend" to Pair("Salary", 983128),
            "freelance" to Pair("Freelance", 983750),
            "upwork" to Pair("Freelance", 983750),
            "interest" to Pair("Interest", 983336),
            "dividend" to Pair("Investment", 983636),
            "investment" to Pair("Investment", 983636),
            "groww" to Pair("Investment", 983636),
            "zerodha" to Pair("Investment", 983636),
            "upstox" to Pair("Investment", 983636),
            "refund" to Pair("Refund", 983294),
            "reversed" to Pair("Refund", 983294),
            "cashback" to Pair("Cashback", 983797),
            "gift" to Pair("Gift", 63002)
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

            // 3. Only process SMS/messaging apps and known financial apps
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
        return listOf("sms", "message", "messaging", "mms", "bank").any { lower.contains(it) }
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

        // Step 1: Check if text contains actual transaction signals FIRST
        val hasTransactionSignal = TRANSACTION_SIGNAL_KEYWORDS.any { lowerText.contains(it) }

        // Step 2: Only apply spam filter if no transaction signal found
        // This prevents rejecting valid refund/cashback credit messages
        if (!hasTransactionSignal) {
            for (keyword in SPAM_KEYWORDS) {
                if (lowerText.contains(keyword)) return null
            }
        } else {
            // Even with transaction signals, reject obvious promotions
            val strongSpam = listOf("apply now", "click here", "limited time",
                "download", "subscribe", "promo", "coupon", "win ")
            for (keyword in strongSpam) {
                if (lowerText.contains(keyword)) return null
            }
        }

        // Step 3: Require banking signals OR explicit transaction phrase OR known merchant
        val hasAccount = ACCOUNT_PATTERN.containsMatchIn(text)
        val hasUpiRef = UPI_REF_PATTERN.containsMatchIn(text)
        val hasBalance = BALANCE_PATTERN.containsMatchIn(text)
        val hasBankingSignal = hasAccount || hasBalance || hasUpiRef ||
            lowerText.contains("upi") || lowerText.contains("vpa") ||
            lowerText.contains("imps") || lowerText.contains("neft") ||
            lowerText.contains("rtgs") || lowerText.contains("bank") ||
            lowerText.contains("card") || lowerText.contains("wallet")

        val hasExplicitTransactionPhrase =
            lowerText.contains("paid you") || lowerText.contains("sent you") ||
            lowerText.contains("received from") || lowerText.contains("credited to") ||
            lowerText.contains("credited with") || lowerText.contains("credit of") ||
            lowerText.contains("refund of") || lowerText.contains("refunded") ||
            lowerText.contains("reversed") || lowerText.contains("cashback of") ||
            lowerText.contains("debited from") || lowerText.contains("paid to") ||
            lowerText.contains("you paid") || lowerText.contains("you sent") ||
            lowerText.contains("purchase of")

        val hasMerchant = MERCHANT_CATEGORY_MAP.keys.any { lowerText.contains(it) }

        if (!hasBankingSignal && !hasExplicitTransactionPhrase && !hasMerchant) return null

        // Step 4: Determine debit vs credit
        val isDebit = when {
            // Credit patterns (check first — more specific)
            lowerText.contains("paid you") ||
            lowerText.contains("sent you") ||
            lowerText.contains("received from") -> false

            lowerText.contains("credited to") ||
            lowerText.contains("credited with") ||
            lowerText.contains("credit of") ||
            lowerText.contains("refund of") ||
            lowerText.contains("refunded") ||
            lowerText.contains("reversed") ||
            lowerText.contains("cashback of") -> false

            // Debit patterns
            lowerText.contains("you paid") ||
            lowerText.contains("you sent") ||
            lowerText.contains("paid to") ||
            lowerText.contains("debited from") ||
            lowerText.contains("debited rs") ||
            lowerText.contains("withdrawn") ||
            lowerText.contains("purchase of") -> true

            // General patterns (lower priority)
            lowerText.contains("debited") ||
            lowerText.contains("deducted") -> true

            lowerText.contains("credited") ||
            lowerText.contains("deposited") ||
            lowerText.contains("received") ||
            lowerText.contains("refund") ||
            lowerText.contains("cashback") -> false

            else -> return null
        }

        // Step 5: Extract amount (avoid taking balance amount when both exist)
        val balanceMatch = BALANCE_PATTERN.find(text)
        val allAmounts = AMOUNT_PATTERN.findAll(text).toList()
        if (allAmounts.isEmpty()) return null

        val amountMatch = allAmounts.firstOrNull { match ->
            if (balanceMatch != null) {
                match.range.first < balanceMatch.range.first || match.range.first > balanceMatch.range.last
            } else {
                true
            }
        } ?: allAmounts.first()

        val amountStr = (amountMatch.groupValues[1].ifEmpty { amountMatch.groupValues[2] })
            .replace(",", "")
            .trim()
        val amount = amountStr.toDoubleOrNull() ?: return null
        if (amount <= 0) return null

        val type = if (isDebit) "expense" else "income"
        val (category, icon) = detectCategory(lowerText, type)

        return Transaction(amount, type, category, icon, text.take(100))
    }

    /**
     * Detects category by scanning for known merchant names in the message.
     * Maps directly to Buddy 2.0 categories and IconHelper codepoints.
     */
    private fun detectCategory(text: String, type: String): Pair<String, Int> {
        val incomeCategories = setOf(
            "Salary", "Freelance", "Business", "Investment",
            "Interest", "Refund", "Gift", "Cashback", "Rental Income"
        )

        // Check merchant mapping first (most accurate)
        for ((merchant, categoryPair) in MERCHANT_CATEGORY_MAP) {
            if (text.contains(merchant)) {
                if (type == "income") {
                    if (categoryPair.first in incomeCategories) {
                        return categoryPair
                    }
                    if (text.contains("refund") || text.contains("reversed")) {
                        return Pair("Refund", 983294)
                    }
                    if (text.contains("cashback")) {
                        return Pair("Cashback", 983797)
                    }
                    return Pair("Other", 983074)
                } else {
                    if (categoryPair.first !in incomeCategories) {
                        return categoryPair
                    }
                }
            }
        }

        // Fallbacks if no merchant was matched
        return if (type == "expense") {
            when {
                text.contains("bill") || text.contains("electricity") || text.contains("water") -> Pair("Bills & Utilities", 983265)
                text.contains("recharge") -> Pair("Recharge", 983160)
                text.contains("rent") -> Pair("Rent", 63477)
                text.contains("emi") || text.contains("loan") -> Pair("Bills & Utilities", 983265)
                text.contains("fuel") || text.contains("petrol") || text.contains("diesel") -> Pair("Fuel", 63597)
                text.contains("food") -> Pair("Local Food", 63609)
                text.contains("shopping") -> Pair("Amazon", 63522)
                text.contains("movie") -> Pair("Hotstar", 63584)
                text.contains("cab") || text.contains("taxi") -> Pair("Uber", 63616)
                else -> Pair("Other", 983074)
            }
        } else {
            when {
                text.contains("salary") || text.contains("wage") || text.contains("stipend") -> Pair("Salary", 983128)
                text.contains("refund") || text.contains("reversed") -> Pair("Refund", 983294)
                text.contains("cashback") || text.contains("reward") -> Pair("Cashback", 983797)
                text.contains("interest") -> Pair("Interest", 983336)
                text.contains("dividend") -> Pair("Investment", 983636)
                text.contains("rent") -> Pair("Rental Income", 63489)
                else -> Pair("Other", 983074)
            }
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