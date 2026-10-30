package com.faysarukattil.buddy

import android.content.Context
import android.util.Log
import io.flutter.FlutterInjector
import io.flutter.app.FlutterApplication
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

class BuddyApplication : FlutterApplication() {

    companion object {
        const val TAG = "BuddyApplication"
        const val WIDGET_ENGINE_ID = "buddy_widget_quick_add_engine"

        fun preWarmWidgetEngine(context: Context) {
            val cache = FlutterEngineCache.getInstance()
            if (cache.contains(WIDGET_ENGINE_ID)) {
                Log.d(TAG, "⚡ Widget FlutterEngine already cached and warm")
                return
            }

            try {
                val startMs = System.currentTimeMillis()
                Log.d(TAG, "🚀 Pre-warming dedicated widget FlutterEngine...")

                val engine = FlutterEngine(context.applicationContext)

                // Execute lightweight dedicated entrypoint
                val dartEntrypoint = DartExecutor.DartEntrypoint(
                    FlutterInjector.instance().flutterLoader().findAppBundlePath(),
                    "widgetAddMain"
                )
                engine.dartExecutor.executeDartEntrypoint(dartEntrypoint)

                cache.put(WIDGET_ENGINE_ID, engine)
                val duration = System.currentTimeMillis() - startMs
                Log.d(TAG, "✅ Widget FlutterEngine pre-warmed in ${duration}ms and cached with ID: $WIDGET_ENGINE_ID")
            } catch (e: Exception) {
                Log.e(TAG, "⚠️ Error pre-warming widget FlutterEngine: ${e.message}", e)
            }
        }

        fun reWarmEngine(context: Context) {
            val cache = FlutterEngineCache.getInstance()
            cache.get(WIDGET_ENGINE_ID)?.destroy()
            cache.remove(WIDGET_ENGINE_ID)
            preWarmWidgetEngine(context)
        }
    }

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "📱 BuddyApplication onCreate — initiating background FlutterEngine pre-warm")
        preWarmWidgetEngine(this)
    }
}

