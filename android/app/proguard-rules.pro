# ARL Investor Portal — release ProGuard / R8 rules
#
# Applied via build.gradle.kts:
#   proguardFiles(
#     getDefaultProguardFile("proguard-android-optimize.txt"),
#     "proguard-rules.pro"
#   )
#
# Notes:
#  - The default file (proguard-android-optimize.txt) supplies Android
#    framework keeps. This file adds Flutter + plugin-specific keeps.
#  - Keep this list minimal; over-keeping defeats minification.

# ── Flutter engine + embedding ───────────────────────────────────────
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }

# ── local_auth (biometric prompt) ────────────────────────────────────
-keep class androidx.biometric.** { *; }

# ── path_provider, url_launcher, connectivity_plus, package_info_plus
# (Flutter standard plugins — keep entry points referenced via JNI.)
-keep class io.flutter.plugins.pathprovider.** { *; }
-keep class io.flutter.plugins.urllauncher.** { *; }
-keep class dev.fluttercommunity.plus.connectivity.** { *; }
-keep class dev.fluttercommunity.plus.packageinfo.** { *; }

# ── Hive (cached storage) ────────────────────────────────────────────
# Type adapters use reflection; keep public API.
-keep class * extends io.flutter.embedding.engine.plugins.FlutterPlugin

# ── Supabase / Realtime (no Android-side reflection, but keep gson) ──
# supabase_flutter uses dart:io HTTP + JS interop on web; nothing
# Android-specific to keep, but we leave a placeholder in case future
# native channel code lands.

# ── Kotlin (avoid stripping coroutines metadata used at runtime) ────
-keepclassmembers class kotlin.Metadata { *; }
-keep class kotlin.coroutines.Continuation { *; }
-dontwarn kotlin.**

# ── Suppress noisy warnings from optional deps ───────────────────────
-dontwarn javax.annotation.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**

# ── Google Play Core (deferred components) ──────────────────────────
# Flutter's embedding references PlayStoreSplitApplication +
# SplitInstall* even when the app doesn't use deferred components.
# We don't bundle play-core (no dynamic feature modules), so R8 sees
# the symbols as missing. -dontwarn lets R8 finish; the runtime path
# is dead code in our build.
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }
