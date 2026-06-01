import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:local_auth/local_auth.dart';

/// Legacy biometric helper, kept for the login-screen biometric shortcut.
/// New runtime gating goes through [AppLockService]. Both wrap local_auth
/// so kept behaviour identical, but this one also bails out cleanly on
/// web where local_auth's support is unreliable.
class BiometricGuard {
  static final _auth = LocalAuthentication();

  static Future<bool> isAvailable() async {
    if (kIsWeb) return false;
    try {
      return await _auth.canCheckBiometrics || await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  static Future<bool> authenticate() async {
    if (kIsWeb) return false;
    try {
      return await _auth.authenticate(
        localizedReason: 'Verify your identity to access ARL',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
