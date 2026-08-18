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
