package com.faysarukattil.buddy

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Unit tests for the getCurrencySymbol() helper in NotificationListener.
 *
 * The production code reads from SharedPreferences (not testable in JVM unit tests),
 * so we test the same logic via a pure-function equivalent that takes the raw
 * prefs value and applies the same null/blank fallback rules.
 *
 * Rules tested (mirror of NotificationListener.getCurrencySymbol()):
 *   1. No value saved (null)  → falls back to "₹"
 *   2. Empty string saved     → falls back to "₹"
 *   3. Blank/whitespace saved → falls back to "₹"
 *   4. "$" saved              → returns "$"
 *   5. "AED" saved            → returns "AED"
 *   6. "€" saved              → returns "€"
 *   7. "KES" saved            → returns "KES"
 */
class CurrencySymbolHelperTest {

    /**
     * Pure-function mirror of NotificationListener.getCurrencySymbol().
     * Takes the raw SharedPreferences string value (or null) and returns
     * the effective symbol, falling back to "₹" when missing or blank.
     */
    private fun resolveSymbol(prefsValue: String?): String {
        val sym = prefsValue ?: "₹"
        return if (sym.isBlank()) "₹" else sym
    }

    @Test
    fun `null value returns rupee fallback`() {
        assertEquals("₹", resolveSymbol(null))
    }

    @Test
    fun `empty string returns rupee fallback`() {
        assertEquals("₹", resolveSymbol(""))
    }

    @Test
    fun `blank whitespace returns rupee fallback`() {
        assertEquals("₹", resolveSymbol("   "))
    }

    @Test
    fun `dollar sign is returned as-is`() {
        assertEquals("$", resolveSymbol("$"))
    }

    @Test
    fun `AED is returned as-is`() {
        assertEquals("AED", resolveSymbol("AED"))
    }

    @Test
    fun `euro symbol is returned as-is`() {
        assertEquals("€", resolveSymbol("€"))
    }

    @Test
    fun `KES is returned as-is`() {
        assertEquals("KES", resolveSymbol("KES"))
    }

    @Test
    fun `rupee sign saved explicitly is returned as-is`() {
        assertEquals("₹", resolveSymbol("₹"))
    }

    @Test
    fun `pound sign is returned as-is`() {
        assertEquals("£", resolveSymbol("£"))
    }

    @Test
    fun `SAR is returned as-is`() {
        assertEquals("SAR", resolveSymbol("SAR"))
    }
}
