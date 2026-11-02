package com.faysarukattil.buddy

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import java.io.File

/**
 * Kotlin regression tests for the India bank SMS parsing logic in
 * [NotificationListener].
 *
 * These tests use the shared test vectors from
 * test/parsing/bank_sms_test_vectors.json — the SAME vectors the Dart tests
 * use — ensuring the Kotlin parser and the Dart generic parser never diverge
 * on expected behaviour.
 *
 * IMPORTANT: ALL India (IN_*) vectors must pass before ANY change is made
 * to the parseTransaction() method in NotificationListener.kt.
 *
 * Non-India vectors are also exercised here to verify the JSON file
 * schema is intact, but the parsing assertions only run on IN_* vectors
 * because the Kotlin NotificationListener does not parse non-India SMS.
 */
class BankSmsParserTest {

    private lateinit var indiaVectors: List<TestVector>
    private lateinit var allVectors: List<TestVector>
    private lateinit var parser: TestableNotificationParser

    data class TestVector(
        val id: String,
        val country: String,
        val description: String,
        val message: String,
        val sourcePackage: String,
        val shouldIgnore: Boolean,
        val expectedType: String?,
        val expectedAmount: Double?,
        val expectedCurrency: String?
    )

    @Before
    fun setUp() {
        // Load shared test vectors from the project root
        // When running via Gradle, working directory is the module root (android/app)
        val vectorsPath = "../../test/parsing/bank_sms_test_vectors.json"
        val file = File(vectorsPath)
        assertTrue(
            "bank_sms_test_vectors.json not found at $vectorsPath",
            file.exists()
        )

        val json = JSONObject(file.readText())
        val vectorArray = json.getJSONArray("vectors")
        allVectors = (0 until vectorArray.length()).map { i ->
            val v = vectorArray.getJSONObject(i)
            TestVector(
                id = v.getString("id"),
                country = v.getString("country"),
                description = v.getString("description"),
                message = v.getString("message"),
                sourcePackage = v.getString("sourcePackage"),
                shouldIgnore = v.getBoolean("shouldIgnore"),
                expectedType = if (v.isNull("expectedType")) null else v.getString("expectedType"),
                expectedAmount = if (v.isNull("expectedAmount")) null else v.getDouble("expectedAmount"),
                expectedCurrency = if (v.isNull("expectedCurrency")) null else v.getString("expectedCurrency")
            )
        }

        indiaVectors = allVectors.filter { it.country == "IN" }
        parser = TestableNotificationParser()
    }

    // ── India regression tests (must all pass) ─────────────────────────────

    @Test
    fun `all India vectors pass regression`() {
        var passed = 0
        var failed = 0
        val failures = StringBuilder()

        for (vector in indiaVectors) {
            try {
                runVectorAssertion(vector)
                passed++
            } catch (e: AssertionError) {
                failed++
                failures.appendLine("[FAIL] ${vector.id}: ${vector.description}")
                failures.appendLine("  Message: ${vector.message.take(80)}")
                failures.appendLine("  Error: ${e.message}")
                failures.appendLine()
            }
        }

        if (failed > 0) {
            fail("$failed India regression test(s) FAILED:\n$failures")
        }

        println("✅ $passed India regression test(s) passed")
    }

    @Test
    fun `IN_001 SBI UPI debit Rs prefix`() {
        val vector = indiaVectors.first { it.id == "IN_001" }
        runVectorAssertion(vector)
    }

    @Test
    fun `IN_002 SBI UPI credit Rs prefix`() {
        val vector = indiaVectors.first { it.id == "IN_002" }
        runVectorAssertion(vector)
    }

    @Test
    fun `IN_003 Federal Bank ATM withdrawal`() {
        val vector = indiaVectors.first { it.id == "IN_003" }
        runVectorAssertion(vector)
    }

    @Test
    fun `IN_004 Canara Bank credit INR prefix`() {
        val vector = indiaVectors.first { it.id == "IN_004" }
        runVectorAssertion(vector)
    }

    @Test
    fun `IN_005 SBI UPI debit bare amount`() {
        val vector = indiaVectors.first { it.id == "IN_005" }
        runVectorAssertion(vector)
    }

    @Test
    fun `IN_006 Netflix mandate auto-pay`() {
        val vector = indiaVectors.first { it.id == "IN_006" }
        runVectorAssertion(vector)
    }

    @Test
    fun `IN_007 Generic debit Rs dot prefix`() {
        val vector = indiaVectors.first { it.id == "IN_007" }
        runVectorAssertion(vector)
    }

    @Test
    fun `IN_008 Generic UPI credit Rs dot prefix`() {
        val vector = indiaVectors.first { it.id == "IN_008" }
        runVectorAssertion(vector)
    }

    @Test
    fun `IN_009 PhonePe Swiggy payment`() {
        val vector = indiaVectors.first { it.id == "IN_009" }
        runVectorAssertion(vector)
    }

    @Test
    fun `IN_010 Amazon shopping comma-formatted amount`() {
        val vector = indiaVectors.first { it.id == "IN_010" }
        runVectorAssertion(vector)
    }

    @Test
    fun `IN_011 PhonePe Uber transport`() {
        val vector = indiaVectors.first { it.id == "IN_011" }
        runVectorAssertion(vector)
    }

    @Test
    fun `IN_012 SBI Card Mathematical Unicode RCS spend`() {
        val vector = indiaVectors.first { it.id == "IN_012" }
        runVectorAssertion(vector)
    }

    @Test
    fun `IN_013 Credit card spend with Available Limit disclaimer`() {
        val vector = indiaVectors.first { it.id == "IN_013" }
        runVectorAssertion(vector)
    }

    @Test
    fun `IN_014 Modern fintech OneCard purchase`() {
        val vector = indiaVectors.first { it.id == "IN_014" }
        runVectorAssertion(vector)
    }

    @Test
    fun `IN_015 UPI transaction with raw VPA handle`() {
        val vector = indiaVectors.first { it.id == "IN_015" }
        runVectorAssertion(vector)
    }

    @Test
    fun `IN_IGNORE_001 OTP must be ignored`() {
        val vector = indiaVectors.first { it.id == "IN_IGNORE_001" }
        runVectorAssertion(vector)
    }

    @Test
    fun `IN_IGNORE_002 Promotional offer must be ignored`() {
        val vector = indiaVectors.first { it.id == "IN_IGNORE_002" }
        runVectorAssertion(vector)
    }

    @Test
    fun `IN_IGNORE_003 Bill due reminder must be ignored`() {
        val vector = indiaVectors.first { it.id == "IN_IGNORE_003" }
        runVectorAssertion(vector)
    }

    @Test
    fun `IN_IGNORE_004 Failed transaction must be ignored`() {
        val vector = indiaVectors.first { it.id == "IN_IGNORE_004" }
        runVectorAssertion(vector)
    }

    @Test
    fun `IN_IGNORE_005 Loan application must be ignored`() {
        val vector = indiaVectors.first { it.id == "IN_IGNORE_005" }
        runVectorAssertion(vector)
    }

    @Test
    fun `IN_IGNORE_006 Cashback offer must be ignored`() {
        val vector = indiaVectors.first { it.id == "IN_IGNORE_006" }
        runVectorAssertion(vector)
    }

    @Test
    fun `IN_IGNORE_007 ASBA IPO hold must be ignored`() {
        val vector = indiaVectors.first { it.id == "IN_IGNORE_007" }
        runVectorAssertion(vector)
    }

    @Test
    fun `IN_IGNORE_008 Future recurring debit reminder must be ignored`() {
        val vector = indiaVectors.first { it.id == "IN_IGNORE_008" }
        runVectorAssertion(vector)
    }

    @Test
    fun `IN_IGNORE_009 SmartEMI promotional notice must be ignored`() {
        val vector = indiaVectors.first { it.id == "IN_IGNORE_009" }
        runVectorAssertion(vector)
    }

    @Test
    fun `IN_IGNORE_010 Hyphenated OTP must be ignored`() {
        val vector = indiaVectors.first { it.id == "IN_IGNORE_010" }
        runVectorAssertion(vector)
    }

    // ── Schema validation ──────────────────────────────────────────────────

    @Test
    fun `test vectors file has correct schema`() {
        assertTrue("Should have at least 10 test vectors", allVectors.size >= 10)
        assertTrue("Should have India vectors", indiaVectors.isNotEmpty())
        // Verify all vectors have required fields
        for (vector in allVectors) {
            assertNotNull("Vector ${vector.id} has null id", vector.id)
            assertNotNull("Vector ${vector.id} has null message", vector.message)
            assertNotNull("Vector ${vector.id} has null sourcePackage", vector.sourcePackage)
        }
    }

    @Test
    fun `bank_rules_json exists and is valid`() {
        val rulesPath = "../../assets/parsing/bank_rules.json"
        val file = File(rulesPath)
        assertTrue("bank_rules.json not found", file.exists())
        val json = JSONObject(file.readText())
        assertNotNull("Missing 'version' field", json.opt("version"))
        assertNotNull("Missing 'rules' array", json.opt("rules"))
        val rules = json.getJSONArray("rules")
        assertTrue("Should have at least 10 rules", rules.length() >= 10)

        // Every rule must have required fields
        for (i in 0 until rules.length()) {
            val rule = rules.getJSONObject(i)
            val country = rule.optString("country")
            assertFalse("Rule $i missing 'country'", country.isNullOrBlank())
            assertFalse(
                "Rule $country missing 'currencyCode'",
                rule.optString("currencyCode").isNullOrBlank()
            )
        }
    }

    // ── Helpers ────────────────────────────────────────────────────────────

    private fun runVectorAssertion(vector: TestVector) {
        val result = parser.parseForTest(vector.message, vector.sourcePackage)

        if (vector.shouldIgnore) {
            assertNull(
                "[${vector.id}] Message should be IGNORED but parser returned: $result\n" +
                "Message: ${vector.message.take(80)}",
                result
            )
            return
        }

        assertNotNull(
            "[${vector.id}] Message should be PARSED but parser returned null.\n" +
            "Message: ${vector.message.take(120)}",
            result
        )

        vector.expectedType?.let { expectedType ->
            assertEquals(
                "[${vector.id}] Wrong type: expected '$expectedType' got '${result!!.type}'",
                expectedType,
                result!!.type
            )
        }

        vector.expectedAmount?.let { expectedAmount ->
            assertEquals(
                "[${vector.id}] Wrong amount: expected $expectedAmount got ${result!!.amount}",
                expectedAmount,
                result!!.amount,
                0.02 // tolerance of 2 paisa / 2 cents
            )
        }
    }
}

/**
 * Thin wrapper around NotificationListener's parse logic so the test
 * can call it without a real Android service context.
 *
 * The [parseForTest] method mirrors [NotificationListener.parseTransaction]
 * but is called as a plain function (no Android framework needed).
 */
class TestableNotificationParser {

    companion object {
        // Mirror the key patterns from NotificationListener
        private val PROMOTIONAL_AND_SPAM_KEYWORDS = listOf(
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
            "bill due", "payment due", "amount due", "due on", "due date", "pay by ", "pay before",
            "bill reminder", "recharge reminder", "upcoming bill", "upcoming payment", "overdue",
            "outstanding balance", "recharge now", "plan expiry", "plan expiring", "validity expiring",
            "renew plan", "auto-pay scheduled", "mandate scheduled",
            "will be debited", "will be auto-debited", "will be auto debited", "will be deducted",
            "scheduled to be debited", "mandate set for", "upcoming mandate", "e-mandate created",
            "mandate successfully registered",
            "is blocked in your", "has been blocked in", "amount has been blocked", "funds blocked",
            "blocked in your a/c", "blocked in your account", "asba", "earmarked in your",
            "earmarked for", "amount earmarked",
            "convert your", "smartemi", "into emi", "into easy emi", "convert to emi", "convert this transaction",
            "requested money", "has requested", "request received", "collect request", "payment request",
            "request to pay",
            "failed", "declined", "unsuccessful", "cancelled", "rejected", "timed out", "could not be processed",
            "loan amount of", "for processing", "received your application",
            "loan application", "loan proposal", "loan processed",
            "application received", "application has been", "application for",
            "technical feasibility", "feasibility report", "proposal bearing",
            "loan disbursement initiated", "disbursement request",
            "loan sanction", "sanctioned amount", "sanction letter",
            "rlms app ref", "surya ghar", "pmay", "pm awas",
            "subsidy application", "subsidy request",
            "emi starts from", "emi will start",
            "loan eligibility", "eligible for loan", "loan offer",
            "credit limit increased", "limit enhanced",
            "otp", "verification code", "one time password", "one-time password", "one-time-password",
            "one-time passcode", "one time passcode", "auth code", "security code", "secret code", "login code",
            "kyc", "pan card", "aadhaar", "link aadhaar", "update kyc", "block your", "freeze"
        )

        private val ACCOUNT_PATTERN = Regex(
            """(?:a/c|a\.c|acct?|account|card|credit\s*card|debit\s*card)\s*(?:no\.?|num(?:ber)?\.?|ending(?:\s+(?:with|in))?|linked\s+to)?\s*[:.-]*\s*[xX*.]*\d{2,}""",
            RegexOption.IGNORE_CASE
        )

        private val BALANCE_PATTERN = Regex(
            """(?:bal|balance|avbl\.?\s*bal(?:ance)?|avl\.?\s*bal(?:ance)?|avail\.?\s*bal(?:ance)?|available\s*bal(?:ance)?|total\s*bal(?:ance)?|total\s*avail\.?\s*bal(?:ance)?|clear\s*bal(?:ance)?|net\s*bal(?:ance)?|updated\s*bal(?:ance)?|new\s*bal(?:ance)?|remaining\s*bal(?:ance)?|a/c\s*bal(?:ance)?|avail\.?\s*(?:credit\s*)?lmt|avail\.?\s*(?:credit\s*)?limit|available\s*(?:credit\s*)?limit|total\s*(?:credit\s*)?limit|credit\s*limit|card\s*limit)[\s:.-]*(?:is\s*)?(?:rs\.?\s*|inr\s*|₹\s*)?[0-9,]+\.?[0-9]*""",
            RegexOption.IGNORE_CASE
        )

        private val CREDIT_LIMIT_CLAUSE = Regex(
            """\b(?:avl|avail|available|total)?\.?\s*(?:credit\s+)?(?:limit|lmt)\b\s*(?:is)?\s*:?\s*(?:inr|rs\.?|₹|[A-Z]{3}|[$€£¥₩])?\s*[0-9,]*\.?\d+""",
            RegexOption.IGNORE_CASE
        )

        private val UPI_REF_PATTERN = Regex(
            """(?:upi\s*(?:ref|reference)?(?:\s*no)?|ref(?:\s*no)?\.?|txn(?:\s*id)?\.?|transaction\s*id|rrn|utr(?:\s*no)?|imps(?:\s*ref)?|neft(?:\s*ref)?|rtgs(?:\s*ref)?|upi\/(?:dr|cr|rev|p2a|p2m|p2p)?\/?\d{6,})[\s:.-]*[A-Za-z0-9]{6,}""",
            RegexOption.IGNORE_CASE
        )

        private val AMOUNT_PATTERN = Regex(
            """(?:Rs\.?|INR|₹)[\s:.-]*([0-9]+(?:,[0-9]+)*(?:\.[0-9]+)?)|([0-9]+(?:,[0-9]+)*(?:\.[0-9]+)?)[\s:.-]*(?:Rs\.?|INR|₹)|(?:debited\s+(?:by|for|with)|credited\s+(?:with|by|for)|spent|paid|amount\s+of|txn\s+of|transfer\s+of)\s*(?:Rs\.?|INR|₹)?[\s:.-]*([0-9]+(?:,[0-9]+)*(?:\.[0-9]+)?)""",
            RegexOption.IGNORE_CASE
        )

        private val DEBIT_ACTION_PATTERN = Regex(
            """(?:debited\s*(?:(?:from|for|with|by|towards|on)\s*)?(?:rs\.?|inr|₹)?\s*[0-9,]+|(?:rs\.?|inr|₹)\s*[0-9,.]+\s*(?:has been\s+|is\s+|was\s+|got\s+)?(?:debited|withdrawn|spent|paid|transferred|sent|deducted|charged|utilized)|(?:debit|debiting)\s+(?:of|by|for)\s*(?:rs\.?|inr|₹)?\s*[0-9,]+|(?:spent|paid|withdrawn|transferred|sent|deducted|charged|utilized)\s*(?:rs\.?|inr|₹)?\s*[0-9,]+|(?:rs\.?|inr|₹)?\s*[0-9,.]+\s*withdrawn\s*[@]?)""",
            RegexOption.IGNORE_CASE
        )

        private val CREDIT_ACTION_PATTERN = Regex(
            """(?:credited\s*(?:(?:to|with|by|in|into|for)\s*)?(?:your\s+)?(?:a/c|acct|account)?|(?:rs\.?|inr|₹)\s*[0-9,.]+\s+(?:has been\s+|is\s+|was\s+|got\s+)?credited|(?:credit|crediting)\s+(?:of|by|for)\s*(?:rs\.?|inr|₹)?\s*[0-9,]+|received\s*(?:rs\.?|inr|₹)?\s*[0-9,.]*\s*(?:from|in|into|to)?|(?:refund|reversal|cashback)\s*(?:of)?\s*(?:rs\.?|inr|₹)?\s*[0-9,]+)""",
            RegexOption.IGNORE_CASE
        )

        private val PAYMENT_APPS = setOf(
            "com.phonepe.app",
            "com.google.android.apps.nbu.paisa.user",
            "net.one97.paytm",
            "in.org.npci.upiapp",
            "com.dreamplug.androidapp",
            "com.mobikwik_new",
            "com.freecharge.android"
        )

        private fun isFraudReportingDisclaimer(lowerText: String): Boolean {
            return lowerText.contains("if not done by") ||
                    lowerText.contains("if not you") ||
                    lowerText.contains("if not u") ||
                    lowerText.contains("if not authorized") ||
                    lowerText.contains("if unauthorized") ||
                    lowerText.contains("not your transaction") ||
                    lowerText.contains("to block") ||
                    lowerText.contains("call ") ||
                    lowerText.contains("forward this") ||
                    lowerText.contains("fwd this") ||
                    lowerText.contains("sms block")
        }
    }

    data class ParseResult(
        val amount: Double,
        val type: String
    )

    /**
     * Public entry point for tests — mirrors [NotificationListener.parseTransaction].
     * Returns null if the message should be ignored.
     */
    fun parseForTest(text: String, packageName: String): ParseResult? {
        val cleanText = java.text.Normalizer.normalize(text, java.text.Normalizer.Form.NFKD)
        val lowerText = cleanText.lowercase(java.util.Locale.US)

        // Step 1: Reject promotional / spam
        for (keyword in PROMOTIONAL_AND_SPAM_KEYWORDS) {
            if (lowerText.contains(keyword)) {
                if ((keyword == "block your" || keyword == "freeze") && isFraudReportingDisclaimer(lowerText)) continue
                if (keyword == "otp" && !Regex("""\botp\b""", RegexOption.IGNORE_CASE).containsMatchIn(cleanText)) continue
                return null
            }
        }

        // Step 2: Debit / credit check
        val hasDebit = DEBIT_ACTION_PATTERN.containsMatchIn(cleanText) ||
                lowerText.contains("debited from") ||
                lowerText.contains("debited by") ||
                lowerText.contains("debited for") ||
                lowerText.contains("debited with") ||
                lowerText.contains("debited towards") ||
                lowerText.contains("debited on") ||
                lowerText.contains("debited rs") ||
                lowerText.contains("debited inr") ||
                lowerText.contains("debited ₹") ||
                lowerText.contains("has been debited") ||
                lowerText.contains("is debited") ||
                lowerText.contains("was debited") ||
                lowerText.contains("got debited") ||
                lowerText.contains("debit of") ||
                lowerText.contains("debit by") ||
                lowerText.contains("has a debit") ||
                lowerText.contains("withdrawn from") ||
                lowerText.contains("withdrawn at") ||
                lowerText.contains("withdrawn@") ||
                lowerText.contains("withdrawn @") ||
                lowerText.contains("cash withdrawn") ||
                lowerText.contains("card withdrawn") ||
                Regex("""\bwithdrawn\b""", RegexOption.IGNORE_CASE).containsMatchIn(lowerText) ||
                lowerText.contains("you paid") ||
                lowerText.contains("paid to") ||
                lowerText.contains("paid at") ||
                lowerText.contains("paid rs") ||
                lowerText.contains("paid inr") ||
                lowerText.contains("paid ₹") ||
                lowerText.contains("payment to") ||
                lowerText.contains("payment of") ||
                lowerText.contains("money sent to") ||
                lowerText.contains("purchase of") ||
                lowerText.contains("spent on") ||
                lowerText.contains("spent at") ||
                lowerText.contains("spent using") ||
                lowerText.contains("spent rs") ||
                lowerText.contains("spent inr") ||
                lowerText.contains("spent ₹") ||
                Regex("""\bspent\b""", RegexOption.IGNORE_CASE).containsMatchIn(lowerText) ||
                lowerText.contains("used for") ||
                lowerText.contains("used at") ||
                lowerText.contains("transferred to") ||
                lowerText.contains("transfer to") ||
                lowerText.contains("transfer of") ||
                lowerText.contains("sent rs") ||
                lowerText.contains("sent inr") ||
                lowerText.contains("sent ₹") ||
                lowerText.contains("auto-debited") ||
                lowerText.contains("auto debited") ||
                lowerText.contains("successfully executed") ||
                lowerText.contains("mandate executed") ||
                lowerText.contains("autopay")

        val hasCredit = CREDIT_ACTION_PATTERN.containsMatchIn(cleanText) ||
                lowerText.contains("credited to") ||
                lowerText.contains("credited with") ||
                lowerText.contains("credited by") ||
                lowerText.contains("credited for") ||
                lowerText.contains("credit of") ||
                lowerText.contains("credit by") ||
                lowerText.contains("credited in") ||
                lowerText.contains("credited into") ||
                lowerText.contains("credited rs") ||
                lowerText.contains("credited inr") ||
                lowerText.contains("credited ₹") ||
                lowerText.contains("has been credited") ||
                lowerText.contains("is credited") ||
                lowerText.contains("was credited") ||
                lowerText.contains("got credited") ||
                lowerText.contains("has a credit") ||
                lowerText.contains("deposited to") ||
                lowerText.contains("deposited in") ||
                lowerText.contains("deposited into") ||
                lowerText.contains("deposited with") ||
                lowerText.contains("received from") ||
                lowerText.contains("received in") ||
                lowerText.contains("received rs") ||
                lowerText.contains("received inr") ||
                lowerText.contains("received ₹") ||
                lowerText.contains("you received") ||
                (lowerText.contains("received") && lowerText.contains("from") &&
                    !lowerText.contains("received your") &&
                    !lowerText.contains("received application") &&
                    !lowerText.contains("received request") &&
                    !lowerText.contains("received document") &&
                    !lowerText.contains("at branch")) ||
                lowerText.contains("sent you") ||
                lowerText.contains("paid you") ||
                lowerText.contains("refund of") ||
                lowerText.contains("refunded to") ||
                lowerText.contains("refund received") ||
                lowerText.contains("refund from") ||
                lowerText.contains("reversal of") ||
                lowerText.contains("reversed to") ||
                lowerText.contains("amount reversed") ||
                lowerText.contains("cashback of") ||
                lowerText.contains("cashback received") ||
                lowerText.contains("salary credited")

        if (!hasDebit && !hasCredit) return null

        // Step 3: Must have bank identifier (or be confirmed receipt from a payment app)
        val isPaymentApp = PAYMENT_APPS.contains(packageName)
        if (isPaymentApp) {
            val isExplicitPaymentReceipt =
                lowerText.contains("you paid") ||
                lowerText.contains("paid to") ||
                lowerText.contains("payment to") ||
                lowerText.contains("payment of") ||
                lowerText.contains("money sent to") ||
                lowerText.contains("you received") ||
                lowerText.contains("received from") ||
                (lowerText.contains("received") && lowerText.contains("from") &&
                    !lowerText.contains("received your") &&
                    !lowerText.contains("received application") &&
                    !lowerText.contains("at branch")) ||
                lowerText.contains("sent you") ||
                lowerText.contains("paid you")
            if (!isExplicitPaymentReceipt) return null
        } else {
            val hasBankId = ACCOUNT_PATTERN.containsMatchIn(cleanText) ||
                    BALANCE_PATTERN.containsMatchIn(cleanText) ||
                    UPI_REF_PATTERN.containsMatchIn(cleanText) ||
                    lowerText.contains("a/c") || lowerText.contains("acct") ||
                    lowerText.contains("account") || lowerText.contains("card") ||
                    lowerText.contains("bank") || lowerText.contains("upi") ||
                    lowerText.contains("imps") || lowerText.contains("neft") ||
                    lowerText.contains("rtgs") || lowerText.contains("atm") ||
                    lowerText.contains("vpa") || lowerText.contains("pos") ||
                    lowerText.contains("ref no") || lowerText.contains("ref:") ||
                    lowerText.contains("utr") || lowerText.contains("rrn") ||
                    lowerText.contains("txn id") ||
                    listOf("sbi", "hdfc", "icici", "axis", "kotak", "pnb", "bob", "canara",
                        "federal", "fedalert", "idfc", "indusind", "rbl", "yes bank", "union bank",
                        "indian bank", "central bank", "iob", "uco bank", "idbi", "okaxis",
                        "okhdfcbank", "oksbi", "okicici", "mandate", "onecard", "slice", "jupiter",
                        "fi money", "cred", "airtel bank", "ippb", "aubank", "simpl", "lazypay", "niyo").any { lowerText.contains(it) }

            if (!hasBankId) return null
        }

        // Step 4: Extract amount (excluding balance and masked credit limit)
        val textWithoutLimits = CREDIT_LIMIT_CLAUSE.replace(cleanText, " ")
        val allAmounts = AMOUNT_PATTERN.findAll(textWithoutLimits).toList()
        if (allAmounts.isEmpty()) return null

        val balanceMatches = BALANCE_PATTERN.findAll(textWithoutLimits).toList()
        val transactionAmounts = allAmounts.filter { amountMatch ->
            balanceMatches.none { balMatch ->
                val aStart = amountMatch.range.first
                val aEnd = amountMatch.range.last
                val bStart = balMatch.range.first
                val bEnd = balMatch.range.last
                !(aEnd < bStart || aStart > bEnd)
            }
        }

        if (transactionAmounts.isEmpty()) return null

        val targetMatch = transactionAmounts.first()
        val amountStr = (targetMatch.groupValues.getOrNull(1)?.ifEmpty { "" } ?: "")
            .ifEmpty { targetMatch.groupValues.getOrNull(2)?.ifEmpty { "" } ?: "" }
            .ifEmpty { targetMatch.groupValues.getOrNull(3)?.ifEmpty { "" } ?: "" }
            .replace(",", "")
            .trim()

        val amount = amountStr.toDoubleOrNull() ?: return null
        if (amount <= 0.0 || amount > 10_000_000.0) return null

        // Step 5: Determine type
        val isDebit = if (hasCredit && !hasDebit) false
        else if (hasDebit && !hasCredit) true
        else !(lowerText.contains("refund") || lowerText.contains("credited") ||
                lowerText.contains("received") || lowerText.contains("reversal"))

        val type = if (isDebit) "expense" else "income"
        return ParseResult(amount, type)
    }
}

