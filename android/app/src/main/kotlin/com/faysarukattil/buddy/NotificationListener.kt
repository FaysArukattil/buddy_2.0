package com.faysarukattil.buddy

import android.content.ComponentName
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

        // SMS / Messaging apps — banks always send SMS for actual transactions
        private val SMS_APPS = setOf(
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
            "com.transsion.mobile.message"
        )

        // UPI & Payment apps (they send transaction confirmations)
        private val PAYMENT_APPS = setOf(
            "com.phonepe.app",
            "com.google.android.apps.nbu.paisa.user",  // Google Pay
            "net.one97.paytm",                        // Paytm
            "in.org.npci.upiapp",                     // BHIM UPI
            "com.dreamplug.androidapp",               // CRED
            "com.mobikwik_new",
            "com.freecharge.android"
        )

        // Official Mobile Banking Apps
        private val BANK_APPS = setOf(
            "com.fedmobile",                          // Federal Bank (FedMobile)
            "com.sbi.SBIFreedomPlus",                 // YONO SBI
            "com.csam.icici.bank.imobile",            // iMobile (ICICI)
            "com.hdfc.retail",                        // HDFC MobileBanking
            "com.axis.mobile",                        // Axis Mobile
            "com.msf.kbank.mobile",                   // Kotak Mobile Banking
            "com.kotak.mobile.banking",
            "com.bankofbaroda.mconnect",              // bob World
            "com.canaaborbank.mobility",              // Canara ai1
            "com.idfcfirst.bank"                      // IDFC FIRST Bank
        )

        private val FINANCIAL_APPS = SMS_APPS + PAYMENT_APPS + BANK_APPS

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

        // Strict promotional and spam keywords — notifications containing ANY of these are rejected immediately.
        // This filter is MANDATORY and NEVER bypassed.
        private val PROMOTIONAL_AND_SPAM_KEYWORDS = listOf(
            // Promotional incentives & reward offers
            "get up to", "get upto", "getup to", "getupto",
            "up to rs", "up to inr", "up to ₹", "upto rs", "upto inr", "upto ₹",
            "up to ", "upto ",
            "win up to", "win upto", "stand a chance", "chance to win", "win a ", "win cash", "win rewards",
            "earn up to", "earn upto", "earn cash", "earn rewards", "start earning",
            "flat cashback", "flat rs", "flat ₹", "flat inr", "cashback offer", "cashback on", "cashback when",
            "cashback alert", "cashback waiting", "cashback voucher", "claim cashback", "cashback from",
            "scratch card", "rewards waiting", "unlock rewards", "exclusive offer", "special offer",
            "limited time", "limited period", "hurry", "valid till", "expires on", "expiring soon",
            "discount", "promo code", "coupon code", "use code", "voucher code",
            "congratulations", "congrats", "you've won", "you have won", "you are eligible", "you're eligible",
            "pre-approved", "pre approved", "instant loan", "loan approved", "apply for loan",
            "credit card offer", "apply now", "click here", "click to", "tap here", "tap to",
            "download now", "install now", "subscribe now", "join now", "avail now", "claim now",
            "invite friends", "refer friends", "referral bonus", "refer & earn", "refer and earn",
            "free recharge", "bonus cash", "spin and win", "spin & win",

            // Reminders & Due Dates (NOT a completed payment)
            "bill due", "payment due", "amount due", "due on", "due date", "pay by ", "pay before",
            "bill reminder", "recharge reminder", "upcoming bill", "upcoming payment", "overdue",
            "outstanding balance", "recharge now", "plan expiry", "plan expiring", "validity expiring",
            "renew plan", "auto-pay scheduled", "mandate scheduled",

            // Payment Requests (someone asking for money, NOT a completed payment)
            "requested money", "has requested", "request received", "collect request", "payment request",
            "request to pay",

            // Failed / Declined transactions
            "failed", "declined", "unsuccessful", "cancelled", "rejected", "timed out", "could not be processed",

            // Security & Admin (not transactions)
            "otp", "verification code", "one time password", "secret code", "login code",
            "kyc", "pan card", "aadhaar", "link aadhaar", "update kyc", "block your", "freeze"
        )

        // Bank account patterns — matching A/c XX1549, a/c X1549, A/c ending 1234, etc.
        private val ACCOUNT_PATTERN = Regex(
            """(?:a/c|a\.c|acct?|account)\s*(?:no\.?|ending)?\s*[xX*]*\d{2,}""",
            RegexOption.IGNORE_CASE
        )

        // UPI Reference / RRN / Transaction ID pattern
        private val UPI_REF_PATTERN = Regex(
            """(?:upi\s*ref(?:\s*no)?|ref(?:\s*no)?\.?|txn(?:\s*id)?\.?|rrn|utr)[\s:.-]*\d{6,}""",
            RegexOption.IGNORE_CASE
        )

        // Bank balance pattern — matching BAL-Rs.60001.27, Bal Rs 37010.08, Avbl Bal: Rs. 15000, etc.
        private val BALANCE_PATTERN = Regex(
            """(?:bal|balance|avbl\s*bal|avl\s*bal|available\s*bal(?:ance)?|total\s*bal(?:ance)?|clear\s*bal(?:ance)?)[\s:.-]*(?:rs\.?\s*|inr\s*|₹\s*)?[0-9,]+\.?[0-9]*""",
            RegexOption.IGNORE_CASE
        )

        // Amount pattern — must start with a digit so a preceding comma (e.g. "Dear Customer, Rs.200") is not captured
        private val AMOUNT_PATTERN = Regex(
            """(?:Rs\.?\s*|INR\s*|₹\s*)([0-9]+(?:,[0-9]+)*(?:\.[0-9]+)?)|([0-9]+(?:,[0-9]+)*(?:\.[0-9]+)?)\s*(?:Rs\.?|INR|₹)""",
            RegexOption.IGNORE_CASE
        )

        // Explicit debit patterns in bank SMS / UPI text
        private val DEBIT_ACTION_PATTERN = Regex(
            """(?:debited\s*(?:(?:from|for|with|by)\s*)?(?:rs\.?|inr|₹)?\s*[0-9,]+|(?:rs\.?|inr|₹)\s*[0-9,.]+\s+(?:has been\s+)?debited)""",
            RegexOption.IGNORE_CASE
        )

        // Explicit credit patterns in bank SMS / UPI text
        private val CREDIT_ACTION_PATTERN = Regex(
            """(?:credited\s*(?:(?:to|with|by|in)\s*)?(?:your\s+)?(?:a/c|acct|account)?|(?:rs\.?|inr|₹)?\s*[0-9,.]+\s+(?:has been\s+)?credited|received\s*(?:rs\.?|inr|₹)?\s*[0-9,.]*\s*(?:from|in))""",
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
        Log.d(TAG, "⚠️ Listener disconnected — requesting rebind")
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.N) {
            try {
                requestRebind(ComponentName(this, NotificationListener::class.java))
            } catch (e: Exception) {
                Log.e(TAG, "Failed to request rebind: ${e.message}")
            }
        }
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

            // 4. Extract notification text (combining all potential OEM fields: bigText, textLines, text, subText)
            val extras = sbn.notification.extras
            val title = extras.getCharSequence("android.title")?.toString() ?: ""
            val text = extras.getCharSequence("android.text")?.toString() ?: ""
            val bigText = extras.getCharSequence("android.bigText")?.toString() ?: ""
            val textLines = extras.getCharSequenceArray("android.textLines")
            val linesContent = textLines?.joinToString(" ") { it.toString() } ?: ""
            val subText = extras.getCharSequence("android.subText")?.toString() ?: ""

            val content = when {
                bigText.isNotEmpty() -> bigText
                linesContent.isNotEmpty() -> linesContent
                text.isNotEmpty() -> text
                else -> subText
            }

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
            val transaction = parseTransaction(fullText, pkg) ?: return

            Log.d(TAG, "💰 Transaction detected: ₹${transaction.amount} ${transaction.type} (${transaction.category})")

            // 8. Generate hash and check for duplicates
            val hash = generateHash("$fullText|${System.currentTimeMillis()}")

            val buddyPrefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            if (buddyPrefs.contains("${KEY_PREFIX}txn_$hash")) {
                Log.d(TAG, "⚠️ Duplicate hash — skipping")
                return
            }

            // 9. Check if the same amount was already recorded today (calendar day / 24h)
            val sameAmountSeen = isSameAmountSeenToday(buddyPrefs, transaction.amount, transaction.type)

            if (sameAmountSeen) {
                // Store as pending and ask user to confirm via notification
                storePendingTransaction(buddyPrefs, hash, transaction, pkg)
                showDuplicateConfirmationNotification(hash, transaction)
                Log.d(TAG, "⚠️ Same amount (₹${transaction.amount}) already seen today — asking user to confirm")
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
        // Universal OEM SMS check: matches user's active default SMS app on ANY device
        try {
            val defaultSmsPkg = android.provider.Telephony.Sms.getDefaultSmsPackage(this)
            if (defaultSmsPkg != null && defaultSmsPkg.equals(packageName, ignoreCase = true)) {
                return true
            }
        } catch (_: Exception) {}

        if (FINANCIAL_APPS.contains(packageName)) return true
        val lower = packageName.lowercase()
        return listOf("sms", "message", "messaging", "mms", "bank", "pay").any { lower.contains(it) }
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

    private fun parseTransaction(text: String, packageName: String): Transaction? {
        val lowerText = text.lowercase()

        // ────────────────────────────────────────────────────────────────
        // STEP 1: Mandatory Promotional, Spam, Offer, & Request Rejection
        // ZERO EXCEPTIONS — ANY matching keyword causes immediate discard.
        // ────────────────────────────────────────────────────────────────
        for (keyword in PROMOTIONAL_AND_SPAM_KEYWORDS) {
            if (lowerText.contains(keyword)) {
                Log.d(TAG, "🚫 Rejected spam/promotional message (keyword '$keyword'): ${text.take(60)}")
                return null
            }
        }

        // ────────────────────────────────────────────────────────────────
        // STEP 2: App classification
        // ────────────────────────────────────────────────────────────────
        val lowerPkg = packageName.lowercase()
        val isSms = SMS_APPS.contains(packageName) ||
            listOf("sms", "message", "messaging", "mms").any { lowerPkg.contains(it) }
        val isPaymentApp = PAYMENT_APPS.contains(packageName)
        val isBankApp = BANK_APPS.contains(packageName) || lowerPkg.contains("bank")

        // ────────────────────────────────────────────────────────────────
        // STEP 3: Debit vs Credit Action Determination
        // Must contain an explicit, completed transaction action verb.
        // ────────────────────────────────────────────────────────────────
        val hasDebitVerb = DEBIT_ACTION_PATTERN.containsMatchIn(text) ||
            lowerText.contains("debited from") ||
            lowerText.contains("debited rs") ||
            lowerText.contains("debited inr") ||
            lowerText.contains("debited ₹") ||
            lowerText.contains("has been debited") ||
            lowerText.contains("is debited") ||
            lowerText.contains("withdrawn from") ||
            lowerText.contains("you paid") ||
            lowerText.contains("paid to") ||
            lowerText.contains("payment to") ||
            lowerText.contains("payment of") ||
            lowerText.contains("money sent to") ||
            lowerText.contains("purchase of") ||
            lowerText.contains("spent on")

        val hasCreditVerb = CREDIT_ACTION_PATTERN.containsMatchIn(text) ||
            lowerText.contains("credited to") ||
            lowerText.contains("credited with") ||
            lowerText.contains("credit of") ||
            lowerText.contains("credited in") ||
            lowerText.contains("has been credited") ||
            lowerText.contains("is credited") ||
            lowerText.contains("deposited to") ||
            lowerText.contains("deposited in") ||
            lowerText.contains("received from") ||
            lowerText.contains("you received") ||
            (lowerText.contains("received") && lowerText.contains("from")) ||
            lowerText.contains("sent you") ||
            lowerText.contains("paid you") ||
            lowerText.contains("refund of") ||
            lowerText.contains("refunded to")

        // If it doesn't describe money being debited or credited, it is NOT a transaction.
        if (!hasDebitVerb && !hasCreditVerb) {
            return null
        }

        // ────────────────────────────────────────────────────────────────
        // STEP 4: Source Verification & Anti-Spam Gate
        // - For SMS: Bank SMS in India ALWAYS has an account number (A/c XX1549),
        //   a balance indicator (Bal-Rs.60001), or a UPI/UTR/RRN reference (Ref 614755429328).
        // - For Payment Apps (Google Pay, PhonePe, Paytm): Must have an explicit
        //   past-tense confirmed action ("you paid", "paid to", "received from", etc.)
        // - For Bank Apps: Must have account, balance, or explicit transaction text.
        // ────────────────────────────────────────────────────────────────
        val hasAccount = ACCOUNT_PATTERN.containsMatchIn(text)
        val hasBalance = BALANCE_PATTERN.containsMatchIn(text)
        val hasUpiRef = UPI_REF_PATTERN.containsMatchIn(text)

        if (isSms || isBankApp) {
            // Authentic bank SMS/alerts must have at least one banking identifier
            val hasBankIdentifier = hasAccount || hasBalance || hasUpiRef ||
                lowerText.contains("a/c") || lowerText.contains("acct") ||
                lowerText.contains("upi") || lowerText.contains("imps") ||
                lowerText.contains("neft") || lowerText.contains("rtgs")
            if (!hasBankIdentifier) {
                Log.d(TAG, "🚫 Ignored message without banking identifier: ${text.take(60)}")
                return null
            }
        } else if (isPaymentApp) {
            // Payment apps (GPay, PhonePe, Paytm) send lots of promo notifications.
            // Require explicit payment receipt phrases:
            val isExplicitPaymentReceipt =
                lowerText.contains("you paid") ||
                lowerText.contains("paid to") ||
                lowerText.contains("payment to") ||
                lowerText.contains("payment of") ||
                lowerText.contains("money sent to") ||
                lowerText.contains("you received") ||
                lowerText.contains("received from") ||
                (lowerText.contains("received") && lowerText.contains("from")) ||
                lowerText.contains("sent you") ||
                lowerText.contains("paid you") ||
                (lowerText.contains("cashback credited") && (lowerText.contains("bank") || lowerText.contains("account")))

            if (!isExplicitPaymentReceipt) {
                Log.d(TAG, "🚫 Ignored payment app notification without confirmed receipt action: ${text.take(60)}")
                return null
            }
        }

        // Determine direction: Credit takes precedence if both credit and debit verbs exist (e.g. refund/cashback)
        val isDebit = if (hasCreditVerb && !hasDebitVerb) {
            false
        } else if (hasDebitVerb && !hasCreditVerb) {
            true
        } else {
            if (lowerText.contains("refund") || lowerText.contains("credited") || lowerText.contains("received")) {
                false
            } else {
                true
            }
        }

        // ────────────────────────────────────────────────────────────────
        // STEP 5: Amount Extraction (Balance-Excluded)
        // Never capture the bank balance (e.g., BAL-Rs.60001.27) as the transaction amount!
        // ────────────────────────────────────────────────────────────────
        val allAmounts = AMOUNT_PATTERN.findAll(text).toList()
        if (allAmounts.isEmpty()) return null

        val balanceMatches = BALANCE_PATTERN.findAll(text).toList()

        // Exclude amounts that fall within any balance regex match span
        val transactionAmounts = allAmounts.filter { amountMatch ->
            balanceMatches.none { balMatch ->
                val aStart = amountMatch.range.first
                val aEnd = amountMatch.range.last
                val bStart = balMatch.range.first
                val bEnd = balMatch.range.last
                !(aEnd < bStart || aStart > bEnd)
            }
        }

        if (transactionAmounts.isEmpty()) {
            Log.d(TAG, "🚫 Only balance amount found, no transaction amount in: ${text.take(60)}")
            return null
        }

        // Use the first valid non-balance amount
        val targetMatch = transactionAmounts.first()
        val amountStr = (targetMatch.groupValues[1].ifEmpty { targetMatch.groupValues[2] })
            .replace(",", "")
            .trim()
        val amount = amountStr.toDoubleOrNull() ?: return null
        if (amount <= 0.0 || amount > 10000000.0) return null

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

    private fun isSameAmountSeenToday(prefs: android.content.SharedPreferences, amount: Double, type: String): Boolean {
        // Prune old history entries older than 48h to prevent unbounded pref growth
        pruneOldHistory(prefs)

        val calendar = Calendar.getInstance()
        calendar.set(Calendar.HOUR_OF_DAY, 0)
        calendar.set(Calendar.MINUTE, 0)
        calendar.set(Calendar.SECOND, 0)
        calendar.set(Calendar.MILLISECOND, 0)
        val todayStart = calendar.timeInMillis
        val oneDayAgo = System.currentTimeMillis() - (24 * 60 * 60 * 1000)
        val cutoffTime = minOf(todayStart, oneDayAgo)

        for ((key, value) in prefs.all) {
            if (key.startsWith("${KEY_PREFIX}txn_") ||
                key.startsWith("${KEY_PREFIX}pending_") ||
                key.startsWith("${KEY_PREFIX}history_")) {
                try {
                    val json = JSONObject(value as String)
                    val txnAmount = json.getDouble("amount")
                    val txnType = json.getString("type")
                    val txnTime = json.optLong("timestamp", 0L)

                    // Match if same amount (within 1 paisa) and same type from today / last 24h
                    if (txnType == type && kotlin.math.abs(txnAmount - amount) < 0.01 && txnTime >= cutoffTime) {
                        return true
                    }
                } catch (_: Exception) {
                    // Skip invalid entries
                }
            }
        }

        return false
    }

    private fun pruneOldHistory(prefs: android.content.SharedPreferences) {
        val twoDaysAgo = System.currentTimeMillis() - (48 * 60 * 60 * 1000)
        val editor = prefs.edit()
        var pruned = false
        for ((key, value) in prefs.all) {
            if (key.startsWith("${KEY_PREFIX}history_")) {
                try {
                    val json = JSONObject(value as String)
                    if (json.optLong("timestamp", 0L) < twoDaysAgo) {
                        editor.remove(key)
                        pruned = true
                    }
                } catch (_: Exception) {
                    editor.remove(key)
                    pruned = true
                }
            }
        }
        if (pruned) editor.apply()
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

        val historyJson = JSONObject().apply {
            put("amount", transaction.amount)
            put("type", transaction.type)
            put("timestamp", System.currentTimeMillis())
        }

        prefs.edit()
            .putString("${KEY_PREFIX}txn_$hash", json.toString())
            .putString("${KEY_PREFIX}history_$hash", historyJson.toString())
            .apply()
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

    private fun showDuplicateConfirmationNotification(hash: String, transaction: Transaction) {
        val channelId = "duplicate_confirmations"
        createNotificationChannel(channelId, "Transaction Confirmations", android.app.NotificationManager.IMPORTANCE_HIGH)

        val typeIcon = if (transaction.type == "expense") "💸" else "💰"
        val typeLabel = if (transaction.type == "expense") "Expense" else "Income"
        val formattedAmount = if (transaction.amount % 1.0 == 0.0) {
            "%.0f".format(transaction.amount)
        } else {
            "%.2f".format(transaction.amount)
        }

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
            .setContentTitle("⚠️ Same amount detected today: ₹$formattedAmount")
            .setContentText("$typeIcon ₹$formattedAmount (${transaction.category}) — Not added automatically. Tap Add if new.")
            .setStyle(androidx.core.app.NotificationCompat.BigTextStyle()
                .bigText("$typeIcon ₹$formattedAmount - ${transaction.category} ($typeLabel)\n\nThis amount was already recorded today. To prevent duplicates, it was NOT added automatically.\n\nIf this is a separate transaction, tap \"Add\" below.")
            )
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setPriority(androidx.core.app.NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(false)
            .addAction(android.R.drawable.ic_input_add, "➕ Add", yesPendingIntent)
            .addAction(android.R.drawable.ic_delete, "✕ Ignore", noPendingIntent)
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