package com.faysarukattil.buddy

import android.content.Context
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.util.Locale

/**
 * GlobalBankParser — Kotlin counterpart to lib/parsing/generic_parser.dart.
 *
 * Reads assets/parsing/bank_rules.json from the Flutter APK assets and
 * applies the per-country rules to parse bank/wallet transaction notifications
 * for non-India users.
 *
 * ARCHITECTURE CONSTRAINTS (MUST NOT BE VIOLATED):
 *  1. This parser is ONLY called AFTER the India path in NotificationListener.kt
 *     returns null, AND the saved countryCode is NOT "IN", AND the Remote Config
 *     flag "enable_global_native_parsing" is true.
 *  2. The India parsing path (parseTransaction() in NotificationListener) is
 *     NEVER touched by this file.
 *  3. Everything after parsing (save, dedup, categorization, notifications,
 *     analytics) reuses the SAME code the India path uses.
 *  4. All parsing is on-device. No notification content is uploaded or logged.
 *
 * The result type [ParsedResult] mirrors NotificationListener's internal
 * Transaction data class (amount + type), so the caller can directly pass
 * the result into the existing save/dedup/notification pipeline.
 */
class GlobalBankParser private constructor(
    private val countryCode: String,
    private val currencyCode: String,
    private val currencySymbol: String,
    private val currencyMarkers: List<String>,
    private val amountPattern: Regex,
    private val decimalSeparator: String,
    private val thousandsSeparator: String,
    private val decimalDigits: Int,
    private val debitKeywords: List<String>,
    private val creditKeywords: List<String>,
    private val bankIdentifiers: List<String>,
    private val ignorePatterns: List<String>,
    private val notificationPackages: Set<String>,
    private val senderPatterns: List<String>,
    private val titlePatterns: List<String>,
) {
    data class ParsedResult(
        val amount: Double,
        val type: String, // "expense" or "income"
        val currencyCode: String,
        val parserUsed: String,
    )

    companion object {
        private const val TAG = "GlobalBankParser"

        // Common balance keyword segments to exclude from amount extraction
        private val BALANCE_MARKERS = listOf(
            "bal", "balance", "avl bal", "avbl bal", "avail bal",
            "available bal", "available balance", "avail balance",
            "a/c bal", "saldo", "kontostand", "disponível", "solde",
            "bakiye", "残高", "잔액",
        )

        // Universal ignore patterns applied before country-specific ones
        private val UNIVERSAL_IGNORE = listOf(
            "otp", "one time password", "verification code", "login code",
            "failed", "declined", "unsuccessful", "cancelled", "rejected",
            "bill due", "payment due", "amount due", "due on",
            "requested money", "has requested", "request received",
            "pre-approved", "pre approved", "loan offer", "loan approved",
            "congratulations", "congrats", "click here", "tap here",
            "promo code", "coupon code", "discount code",
        )
    }

    /**
     * Attempt to parse [text] from [sourcePackage].
     * Returns null if:
     *   - text contains a universal or country-specific ignore pattern
     *   - the source package is not in this rule's allowed set
     *   - no bank identifier is found
     *   - no transaction amount is found
     *   - the amount is zero or negative
     */
    fun parse(text: String, sourcePackage: String): ParsedResult? {
        val lower = text.lowercase(Locale.US)

        // Step 1: Source package filter
        if (notificationPackages.isNotEmpty() && !notificationPackages.contains(sourcePackage)) {
            return null
        }

        // Step 2: Universal ignore check
        if (UNIVERSAL_IGNORE.any { lower.contains(it) }) {
            return null
        }

        // Step 3: Country-specific ignore check
        if (ignorePatterns.any { lower.contains(it.lowercase(Locale.US)) }) {
            return null
        }

        // Step 4: Bank identifier check (must have at least one known bank marker)
        if (bankIdentifiers.isNotEmpty()) {
            val hasBankId = bankIdentifiers.any { lower.contains(it.lowercase(Locale.US)) }
            if (!hasBankId) return null
        }

        // Step 5: Extract amounts (excluding balance amounts)
        val allMatches = amountPattern.findAll(text).toList()
        if (allMatches.isEmpty()) return null

        // Find balance marker spans so we can exclude amounts inside them
        val balanceSpans = mutableListOf<Pair<Int, Int>>()
        for (marker in BALANCE_MARKERS) {
            var start = 0
            while (true) {
                val idx = lower.indexOf(marker, start)
                if (idx < 0) break
                balanceSpans.add(Pair(idx, idx + marker.length + 30))
                start = idx + 1
            }
        }

        val transactionMatches = allMatches.filter { m ->
            balanceSpans.none { (bStart, bEnd) ->
                !(m.range.last < bStart || m.range.first > bEnd)
            }
        }

        if (transactionMatches.isEmpty()) return null

        val targetMatch = transactionMatches.first()
        val amountStr = (targetMatch.groupValues.getOrNull(1)?.ifEmpty { null }
            ?: targetMatch.groupValues.getOrNull(2)?.ifEmpty { null }
            ?: targetMatch.groupValues.getOrNull(3)?.ifEmpty { null }
            ?: return null)

        val amount = parseAmount(amountStr) ?: return null
        if (amount <= 0.0 || amount > 1_000_000_000.0) return null

        // Step 6: Determine debit vs credit
        val hasDebit = debitKeywords.any { lower.contains(it.lowercase(Locale.US)) }
        val hasCredit = creditKeywords.any { lower.contains(it.lowercase(Locale.US)) }

        val type = when {
            hasCredit && !hasDebit -> "income"
            hasDebit && !hasCredit -> "expense"
            // Ambiguous — bias toward expense (safer to ask user)
            else -> {
                val refundWords = listOf("refund", "reversal", "cashback", "received", "credited")
                if (refundWords.any { lower.contains(it) }) "income" else "expense"
            }
        }

        return ParsedResult(
            amount = amount,
            type = type,
            currencyCode = currencyCode,
            parserUsed = "global_native_$countryCode",
        )
    }

    /** Whether [sourcePackage] is accepted by this rule's package filter. */
    fun acceptsPackage(sourcePackage: String): Boolean =
        notificationPackages.isEmpty() || notificationPackages.contains(sourcePackage)

    /** Whether [senderOrTitle] matches this rule's sender/title patterns. */
    fun matchesSenderOrTitle(senderOrTitle: String): Boolean {
        val lower = senderOrTitle.lowercase(Locale.US)
        return senderPatterns.any { lower.contains(it.lowercase(Locale.US)) } ||
                titlePatterns.any { lower.contains(it.lowercase(Locale.US)) }
    }

    private fun parseAmount(raw: String): Double? {
        var cleaned = raw.replace(" ", "").replace("\u00a0", "")

        cleaned = if (decimalSeparator == "," && thousandsSeparator == ".") {
            // European / Brazilian / Indonesian format: 1.234,56
            if (cleaned.contains(",")) {
                // Has decimal comma: strip dots, replace comma with period
                cleaned.replace(".", "").replace(",", ".")
            } else {
                // No decimal comma — dots are thousands separators
                cleaned.replace(".", "")
            }
        } else {
            // Standard format: 1,234.56 — commas are thousands
            cleaned.replace(",", "")
        }

        return cleaned.toDoubleOrNull()
    }

    // ── Factory ────────────────────────────────────────────────────────────

    companion object {
        /**
         * Build a [GlobalBankParser] from one JSON rule entry.
         * Returns null if required fields are missing or the pattern is invalid.
         */
        fun fromRule(rule: JSONObject): GlobalBankParser? {
            return try {
                val country = rule.optString("country").uppercase()
                if (country.isEmpty() || country == "IN") return null

                val currencyCode = rule.optString("currencyCode").ifEmpty { return null }
                val currencySymbol = rule.optString("currencySymbol", currencyCode)
                val currencyMarkers = rule.optJSONArray("currencyMarkers").toStringList()
                val debitKeywords = rule.optJSONArray("debitKeywords").toStringList()
                val creditKeywords = rule.optJSONArray("creditKeywords").toStringList()
                val bankIdentifiers = rule.optJSONArray("bankIdentifiers").toStringList()
                val ignorePatterns = rule.optJSONArray("ignorePatterns").toStringList()
                val packages = rule.optJSONArray("notificationPackages").toStringList().toSet()
                val senderPatterns = rule.optJSONArray("senderPatterns").toStringList()
                val titlePatterns = rule.optJSONArray("titlePatterns").toStringList()
                val decimalSep = rule.optString("decimalSeparator", ".")
                val thousandsSep = rule.optString("thousandsSeparator", ",")
                val decimalDigits = rule.optInt("decimalDigits", 2)

                val rawPattern = rule.optString("amountPattern", "")
                val amountRegex = if (rawPattern.isNotEmpty()) {
                    try {
                        Regex(rawPattern, RegexOption.IGNORE_CASE)
                    } catch (e: Exception) {
                        Log.w(TAG, "Invalid amountPattern for $country: ${e.message}")
                        buildFallbackAmountRegex(currencyMarkers, decimalSep)
                    }
                } else {
                    buildFallbackAmountRegex(currencyMarkers, decimalSep)
                }

                GlobalBankParser(
                    countryCode = country,
                    currencyCode = currencyCode,
                    currencySymbol = currencySymbol,
                    currencyMarkers = currencyMarkers,
                    amountPattern = amountRegex,
                    decimalSeparator = decimalSep,
                    thousandsSeparator = thousandsSep,
                    decimalDigits = decimalDigits,
                    debitKeywords = debitKeywords,
                    creditKeywords = creditKeywords,
                    bankIdentifiers = bankIdentifiers,
                    ignorePatterns = ignorePatterns,
                    notificationPackages = packages,
                    senderPatterns = senderPatterns,
                    titlePatterns = titlePatterns,
                )
            } catch (e: Exception) {
                Log.w(TAG, "Failed to build parser from rule: ${e.message}")
                null
            }
        }

        /**
         * Build a fallback amount regex from currency markers when no explicit
         * amountPattern is provided in the JSON rule.
         *
         * Matches:
         *   - Prefix:  MARKER[space]AMOUNT   (e.g. "$ 1,234.56", "AED 500")
         *   - Suffix:  AMOUNT[space]MARKER   (e.g. "1234 EUR")
         *   - Contextual: debit/credit/paid/sent/received AMOUNT
         */
        private fun buildFallbackAmountRegex(
            markers: List<String>,
            decimalSep: String,
        ): Regex {
            val escapedMarkers = markers.joinToString("|") { Regex.escape(it) }
            val numPattern = if (decimalSep == ",")
                "[0-9]+(?:\\.[0-9]+)*(?:,[0-9]+)?"   // European: 1.234,56
            else
                "[0-9]+(?:,[0-9]+)*(?:\\.[0-9]+)?"   // Standard: 1,234.56

            val pattern = if (escapedMarkers.isEmpty()) {
                // No markers — rely on contextual verbs only
                """(?:debited?|credited?|paid|sent|received|charged|withdrawn|transferred?)\s+(?:of\s+)?($numPattern)"""
            } else {
                """(?:$escapedMarkers)\s*($numPattern)|($numPattern)\s*(?:$escapedMarkers)|(?:debited?|credited?|paid|sent|received|charged|withdrawn|transferred?)\s+(?:of\s+)?(?:$escapedMarkers)?\s*($numPattern)"""
            }

            return try {
                Regex(pattern, RegexOption.IGNORE_CASE)
            } catch (e: Exception) {
                // Absolute fallback: match any bare number
                Regex("""([0-9]+(?:[,.][0-9]+)*)""")
            }
        }

        private fun JSONArray?.toStringList(): List<String> {
            if (this == null) return emptyList()
            return (0 until length()).map { optString(it) }.filter { it.isNotEmpty() }
        }
    }
}

/**
 * Registry of [GlobalBankParser] instances, one per country.
 *
 * Lifecycle:
 *  - [load] on app start (from Flutter assets) or when Remote Config delivers
 *    a new bank_rules.json string.
 *  - [parseForCountry] is the main entry point called by NotificationListener.
 *
 * Thread safety: [load] replaces the map atomically via @Volatile. Reads from
 * [parseForCountry] are safe without locking because they only read the map.
 */
class GlobalParserRegistry private constructor() {

    @Volatile
    private var parsers: Map<String, GlobalBankParser> = emptyMap()

    @Volatile
    private var loaded = false

    companion object {
        private const val TAG = "GlobalParserRegistry"
        const val ASSET_PATH = "flutter_assets/assets/parsing/bank_rules.json"
        const val PREFS_KEY_RC_RULES = "flutter.global_parsing_rules_json"
        const val PREFS_KEY_ENABLED = "flutter.enable_global_native_parsing"
        const val PREFS_KEY_COUNTRIES = "flutter.global_parsing_countries"

        val instance: GlobalParserRegistry by lazy { GlobalParserRegistry() }
    }

    /**
     * Load rules from the Flutter bundled asset. Safe to call multiple times;
     * only loads once unless [force] is true.
     */
    fun loadFromAssets(context: Context, force: Boolean = false) {
        if (loaded && !force) return
        try {
            val json = context.assets.open(ASSET_PATH)
                .bufferedReader()
                .use { it.readText() }
            loadFromJson(json)
            Log.d(TAG, "✅ Loaded ${parsers.size} country rule(s) from bundled assets")
        } catch (e: Exception) {
            Log.w(TAG, "⚠️ Failed to load bank_rules.json from assets: ${e.message}")
        }
        loaded = true
    }

    /**
     * Reload rules from a Remote Config-supplied JSON string.
     * Falls back to the already-loaded rules if [json] is invalid.
     */
    fun reloadFromJson(json: String) {
        try {
            loadFromJson(json)
            Log.d(TAG, "✅ Reloaded ${parsers.size} rule(s) from Remote Config JSON")
        } catch (e: Exception) {
            Log.w(TAG, "⚠️ Invalid Remote Config JSON; keeping bundled rules: ${e.message}")
        }
    }

    private fun loadFromJson(json: String) {
        val root = JSONObject(json)
        val rulesArray: JSONArray = root.optJSONArray("rules") ?: return
        val newParsers = mutableMapOf<String, GlobalBankParser>()

        for (i in 0 until rulesArray.length()) {
            val rule = rulesArray.optJSONObject(i) ?: continue
            val country = rule.optString("country").uppercase()
            if (country == "IN") continue // India handled by NotificationListener

            val parser = GlobalBankParser.fromRule(rule) ?: continue
            newParsers[country] = parser
        }

        parsers = newParsers
    }

    /**
     * Returns true if global parsing is enabled (Remote Config flag written
     * to SharedPreferences by the Flutter side).
     */
    fun isEnabled(context: Context): Boolean {
        val prefs = context.getSharedPreferences(
            "FlutterSharedPreferences", Context.MODE_PRIVATE
        )
        return prefs.getBoolean(PREFS_KEY_ENABLED, false)
    }

    /**
     * Returns true if [countryCode] is in the allowed list from Remote Config,
     * or if the list is empty (meaning all countries are allowed when the flag is on).
     */
    fun isCountryAllowed(context: Context, countryCode: String): Boolean {
        val prefs = context.getSharedPreferences(
            "FlutterSharedPreferences", Context.MODE_PRIVATE
        )
        val countriesStr = prefs.getString(PREFS_KEY_COUNTRIES, "") ?: ""
        if (countriesStr.isBlank()) return true // empty = all countries allowed
        val allowed = countriesStr.split(",").map { it.trim().uppercase() }
        return countryCode.uppercase() in allowed
    }

    /**
     * Check if we have a Remote Config-provided JSON to load and apply it.
     */
    fun checkAndApplyRemoteConfigRules(context: Context) {
        val prefs = context.getSharedPreferences(
            "FlutterSharedPreferences", Context.MODE_PRIVATE
        )
        val rcJson = prefs.getString(PREFS_KEY_RC_RULES, null)
        if (!rcJson.isNullOrBlank()) {
            reloadFromJson(rcJson)
        }
    }

    /**
     * Parse a notification for [countryCode].
     *
     * Returns null if:
     *  - No parser is registered for [countryCode]
     *  - The message doesn't match a transaction
     */
    fun parseForCountry(
        text: String,
        sourcePackage: String,
        countryCode: String,
    ): GlobalBankParser.ParsedResult? {
        val parser = parsers[countryCode.uppercase()] ?: return null
        return parser.parse(text, sourcePackage)
    }

    /** Whether a parser is registered for [countryCode]. */
    fun supports(countryCode: String): Boolean =
        countryCode.uppercase() != "IN" && parsers.containsKey(countryCode.uppercase())

    val ruleCount: Int get() = parsers.size
}

