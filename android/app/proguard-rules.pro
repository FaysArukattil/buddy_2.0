# ==============================================================================
# R8 / ProGuard Configuration for Buddy
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. R8 Optimization & Code Shrinking Passes
# ------------------------------------------------------------------------------
-optimizationpasses 5
-allowaccessmodification
-repackageclasses ''

# ------------------------------------------------------------------------------
# 2. Flutter Engine & Plugin Integration
# ------------------------------------------------------------------------------
# Keep Flutter core application entry points
-keep class io.flutter.app.FlutterApplication { *; }
-keep class io.flutter.plugin.common.PluginRegistry$PluginRegistrantCallback { *; }
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }
-keep class io.flutter.embedding.engine.FlutterJNI { *; }
-keep class io.flutter.embedding.android.FlutterActivity { *; }
-keep class io.flutter.embedding.android.FlutterFragmentActivity { *; }

# Keep annotated members
-keepclassmembers class * {
    @androidx.annotation.Keep *;
}

# Keep communication channel interfaces between Flutter and native code
-keep class * implements io.flutter.plugin.common.MethodChannel$MethodCallHandler { *; }
-keep class * implements io.flutter.plugin.common.BasicMessageChannel$MessageHandler { *; }
-keep class * implements io.flutter.plugin.common.EventChannel$StreamHandler { *; }
-keep class * implements io.flutter.embedding.engine.plugins.FlutterPlugin { *; }
-keep class * implements io.flutter.embedding.engine.plugins.activity.ActivityAware { *; }

# ------------------------------------------------------------------------------
# 3. App-Specific Native Components
# ------------------------------------------------------------------------------
-keep class com.faysarukattil.buddy.MainActivity { *; }
-keep class com.faysarukattil.buddy.NotificationListener { *; }
-keep class com.faysarukattil.buddy.NotificationActionReceiver { *; }
-keep class com.faysarukattil.buddy.BootReceiver { *; }

# ------------------------------------------------------------------------------
# 4. Third-Party Libraries (Firebase, Google Play Services, Gson)
# ------------------------------------------------------------------------------
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**
-dontwarn com.google.android.play.core.**
-dontwarn io.flutter.**

-keepattributes *Annotation*
-keepattributes SerializedName
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer

# ------------------------------------------------------------------------------
# 5. Play Console Crash Reporting & Stack Trace Deobfuscation
# ------------------------------------------------------------------------------
-renamesourcefileattribute SourceFile
-keepattributes SourceFile,LineNumberTable
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes Exceptions

# ------------------------------------------------------------------------------
# 6. Google Sign-In & Credential Manager (required for release builds)
# ------------------------------------------------------------------------------
-keep class com.google.android.gms.auth.** { *; }
-keep class com.google.android.gms.common.** { *; }
-keep class com.google.android.gms.auth.api.signin.** { *; }
-keep class com.google.android.gms.auth.api.credentials.** { *; }
-keep class androidx.credentials.** { *; }

# ------------------------------------------------------------------------------
# 7. Strip Verbose and Debug Logging in Release Builds
# ------------------------------------------------------------------------------
-assumenosideeffects class android.util.Log {
    public static boolean isLoggable(java.lang.String, int);
    public static int v(...);
    public static int d(...);
    public static int i(...);
}
