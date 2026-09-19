# Flutter-specific ProGuard rules

# Keep Flutter wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Firebase & Play Services
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**
-dontwarn com.google.android.play.core.**


# Google Sign-In
-keep class com.google.android.gms.auth.** { *; }

# Firestore
-keep class com.google.firebase.firestore.** { *; }

# Keep notification listener and native components
-keep class com.faysarukattil.buddy.NotificationListener { *; }
-keep class com.faysarukattil.buddy.NotificationActionReceiver { *; }
-keep class com.faysarukattil.buddy.BootReceiver { *; }
-keep class com.faysarukattil.buddy.MainActivity { *; }

# Keep annotations
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
-keepattributes Signature
-keepattributes Exceptions

# Gson (used by Firebase)
-keepattributes SerializedName
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer

# Prevent R8 from removing error info
-keepattributes InnerClasses
