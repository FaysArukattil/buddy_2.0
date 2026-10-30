package com.faysarukattil.buddy

import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode
import io.flutter.embedding.engine.FlutterEngineCache

class WidgetAddModalActivity : FlutterActivity() {

    companion object {
        private const val TAG = "WidgetAddModalActivity"
    }

    private var launchStartTime: Long = 0

    override fun onCreate(savedInstanceState: Bundle?) {
        launchStartTime = System.currentTimeMillis()
        val isWarm = FlutterEngineCache.getInstance().contains(BuddyApplication.WIDGET_ENGINE_ID)
        Log.d(TAG, "⚡ Launching WidgetAddModalActivity (engine warm: $isWarm)")
        super.onCreate(savedInstanceState)
    }

    override fun getCachedEngineId(): String? {
        val cache = FlutterEngineCache.getInstance()
        return if (cache.contains(BuddyApplication.WIDGET_ENGINE_ID)) {
            BuddyApplication.WIDGET_ENGINE_ID
        } else {
            Log.w(TAG, "⚠️ Warm engine not found in cache, falling back to on-demand engine")
            null
        }
    }

    override fun shouldDestroyEngineWithHost(): Boolean {
        // Allow activity to destroy the view attachment
        return false
    }

    override fun getBackgroundMode(): BackgroundMode {
        return BackgroundMode.transparent
    }

    override fun getInitialRoute(): String {
        return "/widget-add"
    }

    override fun onFlutterUiDisplayed() {
        super.onFlutterUiDisplayed()
        val duration = System.currentTimeMillis() - launchStartTime
        Log.d(TAG, "🏁 Flutter quick-add UI displayed in ${duration}ms")
    }

    override fun onDestroy() {
        super.onDestroy()
        // Re-warm fresh engine in background for the next tap
        BuddyApplication.reWarmEngine(applicationContext)
    }
}
