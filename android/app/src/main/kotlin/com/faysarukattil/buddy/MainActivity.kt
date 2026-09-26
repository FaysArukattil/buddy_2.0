package com.faysarukattil.buddy

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.util.Log

/**
 * Simplified MainActivity — provides a MethodChannel for Flutter
 * to check notification listener permission status, manage battery
 * optimization settings, and read SharedPreferences.
 *
 * The NotificationListenerService is managed entirely by the OS.
 * No manual service start/stop, no instance tracking, no sync handlers.
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "notification_channel"
        private const val TAG = "MainActivity"
    }

    private lateinit var channel: MethodChannel

    override fun onResume() {
        super.onResume()
        ensureNotificationListenerActive()
    }

    /**
     * Rebinds the NotificationListenerService on devices where the OEM OS
     * (Vivo, Nothing, Xiaomi, Oppo, Samsung) killed or unlinked the listener.
     */
    private fun ensureNotificationListenerActive() {
        if (!isNotificationListenerEnabled()) return

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                NotificationListenerService.requestRebind(
                    ComponentName(applicationContext, NotificationListener::class.java)
                )
                Log.d(TAG, "🔄 NotificationListener rebind requested onResume")
            }
        } catch (e: Exception) {
            Log.d(TAG, "Rebind attempt onResume: ${e.message}")
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        )

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "isNotificationListenerEnabled" -> {
                    // Check if notification listener permission is granted
                    val enabled = isNotificationListenerEnabled()
                    result.success(enabled)
                }
                "getUnsyncedTransactionCount" -> {
                    // Return count of unsynced transactions in SharedPreferences
                    val count = getUnsyncedTransactionCount()
                    result.success(count)
                }
                "openBatterySettings" -> {
                    // Open battery optimization settings
                    openBatteryOptimizationSettings()
                    result.success(true)
                }
                "openAutoStartSettings" -> {
                    // Open autostart settings (OEM-specific)
                    val opened = openAutoStartSettings()
                    result.success(opened)
                }
                "getAppSignatureSha1" -> {
                    try {
                        val packageInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            packageManager.getPackageInfo(packageName, android.content.pm.PackageManager.GET_SIGNING_CERTIFICATES)
                        } else {
                            @Suppress("DEPRECATION")
                            packageManager.getPackageInfo(packageName, android.content.pm.PackageManager.GET_SIGNATURES)
                        }
                        val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            packageInfo.signingInfo?.apkContentsSigners
                        } else {
                            @Suppress("DEPRECATION")
                            packageInfo.signatures
                        }
                        val md = java.security.MessageDigest.getInstance("SHA-1")
                        val sha1List = signatures?.map { sig ->
                            val digest = md.digest(sig.toByteArray())
                            digest.joinToString(":") { String.format("%02X", it) }
                        } ?: emptyList()
                        result.success(sha1List.firstOrNull() ?: "NONE")
                    } catch (e: Exception) {
                        result.success("ERROR: ${e.message}")
                    }
                }
                else -> result.notImplemented()
            }
        }

        Log.d(TAG, "✅ MethodChannel '$CHANNEL' ready")
    }

    private fun isNotificationListenerEnabled(): Boolean {
        val flat = Settings.Secure.getString(
            contentResolver,
            "enabled_notification_listeners"
        )
        return flat != null && flat.contains(applicationContext.packageName)
    }

    private fun getUnsyncedTransactionCount(): Int {
        val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        return prefs.all.keys.count { it.startsWith("flutter.txn_") }
    }

    /**
     * Opens battery optimization settings.
     * On Android 6+, requests ignore battery optimizations for this app.
     * This is critical for devices like Nothing, Vivo, iQOO, Xiaomi, Oppo, Realme
     * where the OS aggressively kills background services.
     */
    private fun openBatteryOptimizationSettings() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                    data = Uri.parse("package:$packageName")
                }
                startActivity(intent)
            } else {
                val intent = Intent(Settings.ACTION_BATTERY_SAVER_SETTINGS)
                startActivity(intent)
            }
        } catch (e: Exception) {
            Log.e(TAG, "⚠️ Could not open battery settings: ${e.message}")
            try {
                val intent = Intent(Settings.ACTION_SETTINGS)
                startActivity(intent)
            } catch (_: Exception) {}
        }
    }

    /**
     * Attempts to open OEM-specific autostart settings.
     * Returns true if successfully opened, false otherwise.
     *
     * Supports: Xiaomi, Oppo, Vivo, iQOO, Huawei, Samsung, OnePlus,
     * Nothing, Realme, Asus, Letv, Meizu.
     */
    private fun openAutoStartSettings(): Boolean {
        val manufacturer = Build.MANUFACTURER.lowercase()
        Log.d(TAG, "📱 Device manufacturer: $manufacturer")

        val intents = when {
            manufacturer.contains("xiaomi") || manufacturer.contains("redmi") -> listOf(
                Intent().setComponent(ComponentName("com.miui.securitycenter", "com.miui.permcenter.autostart.AutoStartManagementActivity")),
                Intent().setComponent(ComponentName("com.miui.securitycenter", "com.miui.powercenter.PowerSettings"))
            )
            manufacturer.contains("oppo") || manufacturer.contains("realme") -> listOf(
                Intent().setComponent(ComponentName("com.coloros.safecenter", "com.coloros.safecenter.permission.startup.StartupAppListActivity")),
                Intent().setComponent(ComponentName("com.coloros.safecenter", "com.coloros.safecenter.startupapp.StartupAppListActivity")),
                Intent().setComponent(ComponentName("com.oppo.safe", "com.oppo.safe.permission.startup.StartupAppListActivity"))
            )
            manufacturer.contains("vivo") || manufacturer.contains("iqoo") -> listOf(
                Intent().setComponent(ComponentName("com.vivo.permissionmanager", "com.vivo.permissionmanager.activity.BgStartUpManagerActivity")),
                Intent().setComponent(ComponentName("com.iqoo.secure", "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity")),
                Intent().setComponent(ComponentName("com.iqoo.secure", "com.iqoo.secure.ui.phoneoptimize.BgStartUpManager")),
                Intent().setComponent(ComponentName("com.vivo.abe", "com.vivo.applicationbehaviorengine.ui.ExcessivePowerManagerActivity"))
            )
            manufacturer.contains("huawei") || manufacturer.contains("honor") -> listOf(
                Intent().setComponent(ComponentName("com.huawei.systemmanager", "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity")),
                Intent().setComponent(ComponentName("com.huawei.systemmanager", "com.huawei.systemmanager.optimize.process.ProtectActivity")),
                Intent().setComponent(ComponentName("com.huawei.systemmanager", "com.huawei.systemmanager.appcontrol.activity.StartupAppControlActivity"))
            )
            manufacturer.contains("samsung") -> listOf(
                Intent().setComponent(ComponentName("com.samsung.android.lool", "com.samsung.android.sm.battery.ui.BatteryActivity")),
                Intent().setComponent(ComponentName("com.samsung.android.lool", "com.samsung.android.sm.ui.battery.BatteryActivity"))
            )
            manufacturer.contains("oneplus") || manufacturer.contains("nothing") -> listOf(
                Intent().setComponent(ComponentName("com.oneplus.security", "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity")),
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.parse("package:$packageName")
                }
            )
            manufacturer.contains("asus") -> listOf(
                Intent().setComponent(ComponentName("com.asus.mobilemanager", "com.asus.mobilemanager.autostart.AutoStartActivity"))
            )
            manufacturer.contains("letv") || manufacturer.contains("leeco") -> listOf(
                Intent().setComponent(ComponentName("com.letv.android.letvsafe", "com.letv.android.letvsafe.AutobootManageActivity"))
            )
            manufacturer.contains("meizu") -> listOf(
                Intent().setComponent(ComponentName("com.meizu.safe", "com.meizu.safe.security.SHOW_APPSEC")),
            )
            else -> listOf(
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.parse("package:$packageName")
                }
            )
        }

        for (intent in intents) {
            try {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                Log.d(TAG, "✅ Opened autostart settings for $manufacturer")
                return true
            } catch (_: Exception) {
                // Try next intent
            }
        }

        // Fallback: open app info page
        try {
            val fallback = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:$packageName")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(fallback)
            return true
        } catch (_: Exception) {}

        return false
    }

    override fun onDestroy() {
        Log.d(TAG, "🛑 MainActivity destroyed")
        super.onDestroy()
    }
}