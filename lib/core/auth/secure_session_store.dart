import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the small pieces of auth state needed for biometric sign-in:
/// last email used, the most-recent refresh token, and a "biometric was
/// previously enabled on this device" flag.
///
/// The flag is what gates the biometric button on the login screen. It
/// is written by SessionManager on every signed-in / token-refreshed
/// event when the server-side `user_settings.biometric_enabled` is true
/// — and cleared by SecurityScreen when the user toggles biometric off.
class SecureSessionStore {
  static const _kEmail = 'arl.auth.last_email';
  static const _kRefreshToken = 'arl.auth.refresh_token';
  static const _kBiometricEnabled = 'arl.auth.biometric_enabled';

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<String?> readEmail() => _storage.read(key: _kEmail);
  Future<String?> readRefreshToken() => _storage.read(key: _kRefreshToken);

  Future<bool> readBiometricEnabled() async {
    final v = await _storage.read(key: _kBiometricEnabled);
    return v == 'true';
  }

  Future<void> saveSession({
    required String email,
    required String refreshToken,
  }) async {
    await _storage.write(key: _kEmail, value: email);
    await _storage.write(key: _kRefreshToken, value: refreshToken);
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    await _storage.write(
      key: _kBiometricEnabled,
      value: enabled ? 'true' : 'false',
    );
  }

  /// Clears the refresh token + biometric flag (kept email for UX so the
  /// field can be prefilled next time). Called on sign-out and when the
  /// biometric setting is turned off.
  Future<void> clearBiometric() async {
    await _storage.delete(key: _kRefreshToken);
    await _storage.delete(key: _kBiometricEnabled);
  }

  Future<void> clearAll() async {
    await _storage.delete(key: _kEmail);
    await _storage.delete(key: _kRefreshToken);
    await _storage.delete(key: _kBiometricEnabled);
  }
}
