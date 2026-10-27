# ==============================================================================
# R8 / ProGuard Configuration for Buddy
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. R8 Optimization & Code Shrinking Passes
# ------------------------------------------------------------------------------
-optimizationpasses 5
-allowaccessmodification
-repackageclasses ''
-overloadaggressively

# ------------------------------------------------------------------------------
# 2. Flutter Engine & Plugin Integration
# ------------------------------------------------------------------------------
-dontwarn io.flutter.plugin.**
-dontwarn android.**

# Keep Flutter main entry points and registrant
-keep class io.flutter.app.FlutterApplication { <init>(); }
-keep class io.flutter.plugins.GeneratedPluginRegistrant {
    public static void registerWith(io.flutter.embedding.engine.FlutterEngine);
}

# Allow FlutterPlugin implementations to be shrunk and obfuscated while preserving instantiation
-if class * implements io.flutter.embedding.engine.plugins.FlutterPlugin
-keep,allowshrinking,allowobfuscation class <1> {
    public <init>();
}

# Keep annotated members
-keepclassmembers class * {
    @androidx.annotation.Keep *;
}

# Preserve method call dispatching while allowing shrinking/obfuscation
-keepclassmembers class * implements io.flutter.plugin.common.MethodChannel$MethodCallHandler {
    public void onMethodCall(io.flutter.plugin.common.MethodCall, io.flutter.plugin.common.MethodChannel$Result);
}
-keepclassmembers class * implements io.flutter.plugin.common.BasicMessageChannel$MessageHandler {
    public void onMessage(java.lang.Object, io.flutter.plugin.common.BasicMessageChannel$Reply);
}
-keepclassmembers class * implements io.flutter.plugin.common.EventChannel$StreamHandler {
    public void onListen(java.lang.Object, io.flutter.plugin.common.EventChannel$EventSink);
    public void onCancel(java.lang.Object);
}

# ------------------------------------------------------------------------------
# 3. App-Specific Native Components
# ------------------------------------------------------------------------------
-keep public class com.faysarukattil.buddy.MainActivity {
    public protected <init>(...);
    public protected <methods>;
}
-keep public class com.faysarukattil.buddy.NotificationListener {
    public protected <init>(...);
    public protected <methods>;
}
-keep public class com.faysarukattil.buddy.NotificationActionReceiver {
    public protected <init>(...);
    public protected <methods>;
}
-keep public class com.faysarukattil.buddy.BootReceiver {
    public protected <init>(...);
    public protected <methods>;
}

# ------------------------------------------------------------------------------
# 4. Third-Party Libraries (Firebase, Google Play Services, Gson)
# ------------------------------------------------------------------------------
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**
-dontwarn com.google.android.play.core.**

-keepattributes *Annotation*
-keepattributes SerializedName
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer

# Credential Manager & Google Sign In (Preserve reflection constructors only, allow shrinking/obfuscation)
-keepclassmembers class androidx.credentials.** {
    public <init>(...);
}
-keepclassmembers class com.google.android.libraries.identity.googleid.** {
    public <init>(...);
}

# ------------------------------------------------------------------------------
# 5. Play Console Crash Reporting & Stack Trace Deobfuscation
# ------------------------------------------------------------------------------
-renamesourcefileattribute SourceFile
-keepattributes SourceFile,LineNumberTable
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes Exceptions

# ------------------------------------------------------------------------------
# 6. Strip Verbose and Debug Logging in Release Builds
# ------------------------------------------------------------------------------
-assumenosideeffects class android.util.Log {
    public static boolean isLoggable(java.lang.String, int);
    public static int v(...);
    public static int d(...);
    public static int i(...);
}
