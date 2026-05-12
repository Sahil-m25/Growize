import 'package:local_auth/local_auth.dart';

class BiometricGuard {
  static final _auth = LocalAuthentication();

  static Future<bool> isAvailable() async {
    return await _auth.canCheckBiometrics || await _auth.isDeviceSupported();
  }

  static Future<bool> authenticate() async {
    return await _auth.authenticate(
      localizedReason: 'Verify your identity to access ARL',
      options: const AuthenticationOptions(biometricOnly: false),
    );
  }
}
