package com.arl.app

// local_auth's BiometricPrompt requires the host Activity to extend
// FragmentActivity. Plain FlutterActivity is NOT a FragmentActivity, so
// `LocalAuthentication.authenticate(...)` throws a PlatformException
// ("no_fragment_activity") and the OS biometric sheet never appears.
// FlutterFragmentActivity is the Flutter-provided FragmentActivity
// subclass — same behaviour as FlutterActivity in every other respect.
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity()
