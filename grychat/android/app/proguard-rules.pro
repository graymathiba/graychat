# Flutter-specific ProGuard rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Keep Firebase classes
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }

# Keep Supabase classes
-keep class io.github.jan.supabase.** { *; }

# Keep Hive classes
-keep class io.hive.** { *; }
-keep class com.google.gson.** { *; }
-keepclassmembers class * extends io.hive.adapters.** { *; }

# Suppress missing Play Core classes (not needed for non-Play Store builds)
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**

# Keep WebRTC
-keep class org.webrtc.** { *; }
-dontwarn org.webrtc.**

# Keep media_kit / libmpv
-keep class com.alexmererind.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn com.alexmererind.**

# Keep socket.io
-keep class io.socket.** { *; }
-dontwarn io.socket.**

# Keep record audio
-keep class com.llfbandit.** { *; }
-dontwarn com.llfbandit.**

# Keep app_links
-keep class com.llfbandit.** { *; }

# Keep pdfx
-keep class com.github.nicehash.** { *; }
-dontwarn com.github.nicehash.**

# Keep permission_handler
-keep class com.baseflow.permissionhandler.** { *; }

# Keep Kotlin coroutines
-keep class kotlinx.coroutines.** { *; }
-dontwarn kotlinx.coroutines.**

# General Android
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod
