# Flutter-specific ProGuard rules

# Keep Flutter wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Firebase
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Google Sign-In
-keep class com.google.android.gms.auth.** { *; }

# Firestore
-keep class com.google.firebase.firestore.** { *; }

# Keep notification listener
-keep class com.example.buddy.NotificationListener { *; }
-keep class com.example.buddy.NotificationActionReceiver { *; }
-keep class com.example.buddy.BootReceiver { *; }

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
