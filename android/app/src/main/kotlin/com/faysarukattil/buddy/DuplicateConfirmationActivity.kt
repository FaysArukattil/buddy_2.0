package com.faysarukattil.buddy

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.util.Log
import android.view.WindowManager
import android.app.AlertDialog
import android.graphics.Color
import android.graphics.drawable.ColorDrawable

/**
 * Popup activity for duplicate transaction confirmation.
 *
 * NOTE: This activity is no longer registered in the manifest.
 * Duplicate confirmation is now handled via notification action buttons.
 * This file is kept for reference but is effectively dead code.
 */
class DuplicateConfirmationActivity : Activity() {

    companion object {
        private const val TAG = "DuplicatePopup"
        const val EXTRA_HASH = "transaction_hash"
        const val EXTRA_AMOUNT = "amount"
        const val EXTRA_TYPE = "type"
        const val EXTRA_CATEGORY = "category"
        const val EXTRA_SIMILAR_COUNT = "similar_count"
        const val EXTRA_NOTE = "note"
    }

    private var transactionHash: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        Log.d(TAG, "🎯 DuplicateConfirmationActivity started")

        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }

        transactionHash = intent.getStringExtra(EXTRA_HASH)
        val amount = intent.getDoubleExtra(EXTRA_AMOUNT, 0.0)
        val type = intent.getStringExtra(EXTRA_TYPE) ?: "expense"
        val category = intent.getStringExtra(EXTRA_CATEGORY) ?: "Other"
        val similarCount = intent.getIntExtra(EXTRA_SIMILAR_COUNT, 0)
        val note = intent.getStringExtra(EXTRA_NOTE) ?: ""

        if (transactionHash == null) {
            Log.e(TAG, "❌ No transaction hash provided!")
            finish()
            return
        }

        showConfirmationDialog(amount, type, category, similarCount, note)
    }

    private fun showConfirmationDialog(
        amount: Double,
        type: String,
        category: String,
        similarCount: Int,
        note: String
    ) {
        val typeIcon = if (type == "expense") "💸" else "💰"
        val typeText = if (type == "expense") "Expense" else "Income"

        val message = """
            |⚠️ Possible Duplicate Transaction
            |
            |$typeIcon Amount: ₹$amount
            |📁 Category: $category
            |📊 Type: $typeText
            |
            |🔄 Found $similarCount similar transaction(s) in the last 24 hours
            |
            |${if (note.isNotEmpty()) "📝 $note\n\n" else ""}Is this a NEW transaction?
        """.trimMargin()

        val dialog = AlertDialog.Builder(this)
            .setTitle("Duplicate Transaction?")
            .setMessage(message)
            .setCancelable(false)
            .setPositiveButton("✅ Yes, Add It") { _, _ ->
                handleUserResponse(true)
            }
            .setNegativeButton("❌ No, Ignore") { _, _ ->
                handleUserResponse(false)
            }
            .create()

        dialog.show()
    }

    private fun handleUserResponse(shouldAdd: Boolean) {
        val hash = transactionHash ?: return

        if (shouldAdd) {
            // Move pending to confirmed in SharedPreferences
            val prefs = getSharedPreferences("buddy_prefs", Context.MODE_PRIVATE)
            val pendingJson = prefs.getString("pending_$hash", null)
            if (pendingJson != null) {
                prefs.edit()
                    .putString("txn_$hash", pendingJson)
                    .remove("pending_$hash")
                    .apply()
                Log.d(TAG, "✅ Transaction confirmed: $hash")
            }
        } else {
            // Remove pending
            val prefs = getSharedPreferences("buddy_prefs", Context.MODE_PRIVATE)
            prefs.edit().remove("pending_$hash").apply()
            Log.d(TAG, "❌ Transaction rejected: $hash")
        }

        finish()
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        Log.d(TAG, "⚠️ Back button pressed — ignoring")
    }
}