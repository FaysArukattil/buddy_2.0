package com.example.buddy

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.util.Log
import android.view.WindowManager
import android.app.AlertDialog
import android.graphics.Color
import android.graphics.drawable.ColorDrawable

/**
 * Popup activity that shows immediately when duplicate transaction is detected
 * Works even when app is closed by appearing as overlay
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
        
        Log.d(TAG, "🎯 ============ DUPLICATE POPUP ACTIVITY STARTED ============")

        // Make this activity show over lockscreen and turn screen on
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

        // Get transaction details from intent
        transactionHash = intent.getStringExtra(EXTRA_HASH)
        val amount = intent.getDoubleExtra(EXTRA_AMOUNT, 0.0)
        val type = intent.getStringExtra(EXTRA_TYPE) ?: "expense"
        val category = intent.getStringExtra(EXTRA_CATEGORY) ?: "Other"
        val similarCount = intent.getIntExtra(EXTRA_SIMILAR_COUNT, 0)
        val note = intent.getStringExtra(EXTRA_NOTE) ?: ""

        Log.d(TAG, "Transaction: ₹$amount | $type | $category")
        Log.d(TAG, "Similar count: $similarCount")
        Log.d(TAG, "Hash: $transactionHash")

        if (transactionHash == null) {
            Log.e(TAG, "❌ No transaction hash provided!")
            finish()
            return
        }

        // Show dialog immediately
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
                Log.d(TAG, "✅ User clicked YES - Adding transaction")
                handleUserResponse(true)
            }
            .setNegativeButton("❌ No, Ignore") { _, _ ->
                Log.d(TAG, "❌ User clicked NO - Ignoring transaction")
                handleUserResponse(false)
            }
            .create()

        // Make dialog appear over other apps
        dialog.window?.setType(WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY)
        
        // Style the dialog
        dialog.window?.setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
        
        dialog.show()

        Log.d(TAG, "✅ Confirmation dialog shown")
    }

    private fun handleUserResponse(shouldAdd: Boolean) {
        val hash = transactionHash ?: return

        // Send response back to Flutter via MainActivity
        val responseIntent = Intent("com.example.buddy.DUPLICATE_RESPONSE").apply {
            putExtra("hash", hash)
            putExtra("shouldAdd", shouldAdd)
        }
        sendBroadcast(responseIntent)

        Log.d(TAG, "📡 Response broadcast sent: shouldAdd=$shouldAdd")

        // Also send to MainActivity if active
        MainActivity.instance?.handleDuplicateResponse(hash, shouldAdd)

        finish()
    }

    override fun onBackPressed() {
        // Prevent back button from dismissing without choice
        Log.d(TAG, "⚠️ Back button pressed - ignoring (user must choose)")
    }
}