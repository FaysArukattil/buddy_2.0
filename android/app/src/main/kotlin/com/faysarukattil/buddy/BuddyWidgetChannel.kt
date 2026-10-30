package com.faysarukattil.buddy

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import io.flutter.plugin.common.MethodChannel

/**
 * Handles the Flutter MethodChannel "com.faysarukattil.buddy/widget".
 *
 * Replaces the home_widget plugin entirely:
 *   • Writes key-value data from Flutter into the shared SharedPreferences file
 *     that BuddyWidgetProvider and BuddyStatsWidgetProvider already read from.
 *   • Triggers AppWidgetManager.notifyAppWidgetViewDataChanged so both providers
 *     re-render immediately.
 */
class BuddyWidgetChannel(private val context: Context) {

    companion object {
        const val CHANNEL_NAME = "com.faysarukattil.buddy/widget"
        // This prefs file name MUST match what BuddyWidgetProvider reads via getData().
        // The home_widget plugin used this convention:
        //   context.getSharedPreferences(packageName + "_HomeWidgetPlugin", Context.MODE_PRIVATE)
        // We keep the same name so we remain 100% compatible with the existing Kotlin providers.
        private fun getPrefs(context: Context): SharedPreferences =
            context.getSharedPreferences(
                context.packageName + "_HomeWidgetPlugin",
                Context.MODE_PRIVATE
            )

        private const val TAG = "BuddyWidgetChannel"
    }

    fun register(messenger: io.flutter.plugin.common.BinaryMessenger) {
        MethodChannel(messenger, CHANNEL_NAME).setMethodCallHandler { call, result ->
            when (call.method) {
                "updateWidget" -> {
                    try {
                        val args = call.arguments as? Map<*, *>
                        if (args != null) {
                            saveToPrefs(args)
                        }
                        triggerWidgetUpdate()
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "❌ updateWidget failed: ${e.message}", e)
                        result.error("WIDGET_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        Log.d(TAG, "✅ BuddyWidgetChannel registered on $CHANNEL_NAME")
    }

    private fun saveToPrefs(args: Map<*, *>) {
        val prefs = getPrefs(context)
        val editor = prefs.edit()

        for ((key, value) in args) {
            val k = key as? String ?: continue
            when (value) {
                is Boolean -> editor.putBoolean(k, value)
                is Int    -> editor.putInt(k, value)
                is Long   -> editor.putLong(k, value)
                is Float  -> editor.putFloat(k, value)
                is Double -> editor.putFloat(k, value.toFloat())
                is String -> editor.putString(k, value)
                else      -> editor.putString(k, value?.toString() ?: "")
            }
        }

        editor.apply()
        Log.d(TAG, "💾 Saved ${args.size} widget prefs keys")
    }

    private fun triggerWidgetUpdate() {
        val manager = AppWidgetManager.getInstance(context)

        val providers = listOf(
            BuddyWidgetProvider::class.java,
            BuddyStatsWidgetProvider::class.java,
            BuddyQuickAddWidgetProvider::class.java
        )

        for (providerClass in providers) {
            val ids = manager.getAppWidgetIds(ComponentName(context, providerClass))
            if (ids.isNotEmpty()) {
                val intent = android.content.Intent(context, providerClass).apply {
                    action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
                }
                context.sendBroadcast(intent)
                Log.d(TAG, "📡 Triggered update for ${ids.size} ${providerClass.simpleName}(s)")
            }
        }
    }
}

