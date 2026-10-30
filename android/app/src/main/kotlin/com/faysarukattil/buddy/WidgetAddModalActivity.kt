package com.faysarukattil.buddy

import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode
import io.flutter.embedding.engine.FlutterEngine
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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Register the widget channel so the quick-add flow can also update the widget
        BuddyWidgetChannel(this).register(flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun getBackgroundMode(): BackgroundMode = BackgroundMode.transparent

    override fun getInitialRoute(): String = "/widget-add"

    override fun onFlutterUiDisplayed() {
        super.onFlutterUiDisplayed()
        val duration = System.currentTimeMillis() - launchStartTime
        Log.d(TAG, "🏁 Flutter quick-add UI displayed in ${duration}ms")
    }

    override fun onDestroy() {
        super.onDestroy()
        BuddyApplication.reWarmEngine(applicationContext)
    }
}
