package com.faysarukattil.buddy

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode

class WidgetAddModalActivity : FlutterActivity() {

    override fun getBackgroundMode(): BackgroundMode {
        return BackgroundMode.transparent
    }

    override fun getInitialRoute(): String {
        return "/widget-add"
    }
}

