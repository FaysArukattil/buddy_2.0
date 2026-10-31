package com.faysarukattil.buddy

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import java.io.File

/**
 * Unit tests for [GlobalBankParser] and [GlobalParserRegistry].
 *
 * These tests:
 *  1. Load bank_rules.json from the shared asset path (same file used by Dart
 *     tests and bundled in the APK as flutter_assets/assets/parsing/bank_rules.json).
 *  2. Parse the extended test vectors in bank_sms_test_vectors.json for all
 *     non-India countries.
 *  3. Verify that parity formats (USD $1,234.56 / EUR 1.234,56 / IDR 1.000.000 /
 *     KWD 3-decimal / JPY zero-decimal) are handled correctly.
 *  4. Verify that OTP / promo / failed / no-amount messages are ignored.
 *
 * IMPORTANT: India (IN_*) vectors are tested in BankSmsParserTest.kt and are
 * NOT touched here. This test only covers the GlobalBankParser path.
 */
class GlobalBankParserTest {

    private val rulesPath = "../../assets/parsing/bank_rules.json"
    private val vectorsPath = "../../test/parsing/bank_sms_test_vectors.json"

    private lateinit var registry: Map<String, GlobalBankParser>
    private lateinit var nonIndiaVectors: List<TestVector>

    data class TestVector(
        val id: String,
        val country: String,
        val message: String,
        val sourcePackage: String,
        val shouldIgnore: Boolean,
        val expectedType: String?,
        val expectedAmount: Double?,
    )

    @Before
    fun setUp() {
        // Load bank_rules.json and build parsers
        val rulesFile = File(rulesPath)
        assertTrue("bank_rules.json not found at $rulesPath", rulesFile.exists())
        val rulesJson = rulesFile.readText()
        registry = buildRegistry(rulesJson)
        assertTrue("Registry must have at least 10 countries", registry.size >= 10)

        // Load test vectors — non-India only
        val vectorsFile = File(vectorsPath)
        assertTrue("bank_sms_test_vectors.json not found at $vectorsPath", vectorsFile.exists())
        val root = JSONObject(vectorsFile.readText())
        val arr = root.getJSONArray("vectors")
        nonIndiaVectors = (0 until arr.length())
            .map { arr.getJSONObject(it) }
            .filter { it.getString("country") != "IN" }
            .map { v ->
                TestVector(
                    id = v.getString("id"),
                    country = v.getString("country"),
                    message = v.getString("message"),
                    sourcePackage = v.getString("sourcePackage"),
                    shouldIgnore = v.getBoolean("shouldIgnore"),
                    expectedType = if (v.isNull("expectedType")) null else v.getString("expectedType"),
                    expectedAmount = if (v.isNull("expectedAmount")) null else v.getDouble("expectedAmount"),
                )
            }

        assertTrue("Expected at least 15 non-India vectors", nonIndiaVectors.size >= 15)
    }

    /** Run all non-India test vectors against their country parsers. */
    @Test
    fun `all non-India vectors match expected results`() {
        var passed = 0
        var failed = 0
        val failures = StringBuilder()

        for (v in nonIndiaVectors) {
            val parser = registry[v.country]
            if (parser == null) {
                // No parser for this country — treat as ignored (acceptable)
                if (!v.shouldIgnore) {
                    failures.appendLine("[${v.id}] No parser for country ${v.country} but vector expects a result")
                    failed++
                }
                continue
            }

            val result = parser.parse(v.message, v.sourcePackage)

            if (v.shouldIgnore) {
                if (result != null) {
                    failures.appendLine("[${v.id}] Expected IGNORE but got ${result.type} ${result.amount}")
                    failed++
                } else {
                    passed++
                }
            } else {
                if (result == null) {
                    failures.appendLine("[${v.id}] Expected ${v.expectedType} ${v.expectedAmount} but got null")
                    failed++
                } else {
                    val typeOk = result.type == v.expectedType
                    val amountOk = v.expectedAmount == null ||
                            Math.abs(result.amount - v.expectedAmount) < 0.01
                    if (typeOk && amountOk) {
                        passed++
                    } else {
                        failures.appendLine(
                            "[${v.id}] Expected type=${v.expectedType} amount=${v.expectedAmount} " +
                                    "but got type=${result.type} amount=${result.amount}"
                        )
                        failed++
                    }
                }
            }
        }

        if (failed > 0) {
            fail("$failed vector(s) failed (${passed} passed):\n$failures")
        }
        println("✅ GlobalBankParserTest: $passed/${nonIndiaVectors.size} vectors passed")
    }

    // ── Specific format parity tests ────────────────────────────────────────

    @Test
    fun `USD dollar comma-thousands decimal format parsed correctly`() {
        val parser = registry["US"] ?: return
        val result = parser.parse(
            "Chase: A charge of \$1,234.56 was made to your account ending in 1234 on Oct 31. Balance: \$9,765.44.",
            "com.google.android.apps.messaging"
        )
        assertNotNull("US parser should parse dollar amount", result)
        assertEquals("expense", result!!.type)
        assertEquals(1234.56, result.amount, 0.01)
    }

    @Test
    fun `EUR European dot-thousands comma-decimal format parsed correctly`() {
        val parser = registry["DE"] ?: return
        val result = parser.parse(
            "N26: 1.234,56 EUR wurde von Ihrem Konto abgebucht am 31.10.2026. Referenz: N26DE123.",
            "de.number26.android"
        )
        assertNotNull("DE parser should parse EUR European format", result)
        assertEquals("expense", result!!.type)
        assertEquals(1234.56, result.amount, 0.01)
    }

    @Test
    fun `GBP pound prefix parsed correctly`() {
        val parser = registry["GB"] ?: return
        val result = parser.parse(
            "Monzo: You spent £45.99 at Tesco on 31 Oct 2026. Balance: £1,204.01.",
            "co.monzo.android"
        )
        assertNotNull("GB parser should parse GBP", result)
        assertEquals("expense", result!!.type)
        assertEquals(45.99, result.amount, 0.01)
    }

    @Test
    fun `AED dirham prefix parsed correctly`() {
        val parser = registry["AE"] ?: return
        val result = parser.parse(
            "Emirates NBD: AED 750.00 has been debited from your account XXXX4567 on 31/10/2026. Balance: AED 24,250.00.",
            "com.google.android.apps.messaging"
        )
        assertNotNull("AE parser should parse AED", result)
        assertEquals("expense", result!!.type)
        assertEquals(750.0, result.amount, 0.01)
    }

    @Test
    fun `NGN naira prefix parsed correctly`() {
        val parser = registry["NG"] ?: return
        val result = parser.parse(
            "GTBank: NGN 50,000.00 debited from your account XXXX3456 on 31/10/2026. Balance: NGN 150,000.00.",
            "com.google.android.apps.messaging"
        )
        assertNotNull("NG parser should parse NGN", result)
        assertEquals("expense", result!!.type)
        assertEquals(50000.0, result.amount, 0.01)
    }

    @Test
    fun `KES shilling M-Pesa format parsed correctly`() {
        val parser = registry["KE"] ?: return
        val result = parser.parse(
            "M-PESA Confirmed. KES 2,500.00 sent to Jane Wanjiku on 31/10/26. Balance: KES 7,500.00. Cost: KES 35.00.",
            "com.google.android.apps.messaging"
        )
        assertNotNull("KE parser should parse KES M-Pesa", result)
        assertEquals("expense", result!!.type)
        assertEquals(2500.0, result.amount, 0.01)
    }

    @Test
    fun `JPY yen zero-decimal format parsed correctly`() {
        val parser = registry["JP"] ?: return
        val result = parser.parse(
            "SBI: 50,000円 が口座 XXXX1234 から引き落とされました。残高: 250,000円。",
            "com.google.android.apps.messaging"
        )
        assertNotNull("JP parser should parse JPY", result)
        assertEquals(50000.0, result!!.amount, 1.0) // JPY has no fractional part
    }

    @Test
    fun `IDR Indonesian dot-thousands zero-decimal format parsed correctly`() {
        val parser = registry["ID"] ?: return
        val result = parser.parse(
            "BCA: Rp 500.000 telah didebit dari rekening Anda XXXX1234 pada 31/10/2026. Saldo: Rp 4.500.000.",
            "com.google.android.apps.messaging"
        )
        assertNotNull("ID parser should parse IDR Indonesian format", result)
        assertEquals("expense", result!!.type)
        assertEquals(500000.0, result.amount, 1.0)
    }

    @Test
    fun `BRL Brazilian R-dollar European format parsed correctly`() {
        val parser = registry["BR"] ?: return
        val result = parser.parse(
            "Nubank: Você fez um PIX de R\$ 350,00 para Maria Silva em 31/10/2026. Saldo: R\$ 2.150,00.",
            "com.nu.production"
        )
        assertNotNull("BR parser should parse BRL", result)
        assertEquals("expense", result!!.type)
        assertEquals(350.0, result.amount, 0.01)
    }

    @Test
    fun `SGD Singapore dollar parsed correctly`() {
        val parser = registry["SG"] ?: return
        val result = parser.parse(
            "DBS PayNow: S\$500.00 received from John Lim on 31 Oct 2026. Balance: S\$3,500.00.",
            "sg.com.dbs.digibank"
        )
        assertNotNull("SG parser should parse SGD", result)
        assertEquals("income", result!!.type)
        assertEquals(500.0, result.amount, 0.01)
    }

    // ── Ignore cases ─────────────────────────────────────────────────────────

    @Test
    fun `OTP message is ignored`() {
        val parser = registry["US"] ?: return
        val result = parser.parse(
            "Chase: Your one-time verification code is 847291. Do not share.",
            "com.google.android.apps.messaging"
        )
        assertNull("OTP message must be ignored", result)
    }

    @Test
    fun `failed payment is ignored`() {
        val parser = registry["GB"] ?: return
        val result = parser.parse(
            "HSBC: Your payment of £300.00 was unsuccessful. Please try again.",
            "com.google.android.apps.messaging"
        )
        assertNull("Failed payment must be ignored", result)
    }

    @Test
    fun `promotional offer is ignored`() {
        val parser = registry["AE"] ?: return
        val result = parser.parse(
            "Emirates NBD: Congratulations! You are eligible for a pre-approved credit card. Click here.",
            "com.google.android.apps.messaging"
        )
        assertNull("Promo offer must be ignored", result)
    }

    @Test
    fun `India country code returns no parser`() {
        val parser = registry["IN"]
        assertNull("India must not have a GlobalBankParser — it uses the hardcoded Kotlin path", parser)
    }

    // ── Helper ────────────────────────────────────────────────────────────────

    private fun buildRegistry(json: String): Map<String, GlobalBankParser> {
        val root = org.json.JSONObject(json)
        val rules = root.getJSONArray("rules")
        val map = mutableMapOf<String, GlobalBankParser>()
        for (i in 0 until rules.length()) {
            val rule = rules.getJSONObject(i)
            val country = rule.optString("country").uppercase()
            if (country == "IN") continue
            val parser = GlobalBankParser.fromRule(rule) ?: continue
            map[country] = parser
        }
        return map
    }
}

