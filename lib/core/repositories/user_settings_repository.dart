import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'package:arl_app/core/supabase/supabase_client.dart';

/// Persists per-user app preferences (biometric toggle, notifications toggle)
/// and the app PIN hash. The DB never sees a plaintext PIN — hashing is done
/// here on the client, salt + iteration count are stored alongside the hash
/// so verification reproduces the same digest.
class UserSettingsRepository {
  static const int _pinIterations = 100000;
  static const int _saltBytes = 16;

  /// Row keyed by current auth uid. Returns null when there is no row yet
  /// (first-time user) or when Supabase is in demo mode.
  Future<Map<String, dynamic>?> mySettings() async {
    final client = ArlSupabase.client;
    final uid = ArlSupabase.currentUserId;
    if (client == null || uid == null) return null;
    return await client
        .from('user_settings')
        .select(
          'user_id, biometric_enabled, notifications_enabled, '
          'app_pin_hash, app_pin_salt, app_pin_iterations, updated_at',
        )
        .eq('user_id', uid)
        .maybeSingle();
  }

  /// Upsert biometric/notifications toggles. Leaves PIN columns untouched.
  Future<void> updateToggles({
    bool? biometricEnabled,
    bool? notificationsEnabled,
  }) async {
    final client = ArlSupabase.requireClient();
    final uid = client.auth.currentUser!.id;
    final payload = <String, dynamic>{
      'user_id': uid,
      if (biometricEnabled != null) 'biometric_enabled': biometricEnabled,
      if (notificationsEnabled != null)
        'notifications_enabled': notificationsEnabled,
    };
    await client.from('user_settings').upsert(payload, onConflict: 'user_id');
  }

  /// Set the PIN for the first time. Generates a random salt and stores
  /// hash(salt + pin) iterated _pinIterations times.
  Future<void> setPin(String pin) async {
    final client = ArlSupabase.requireClient();
    final uid = client.auth.currentUser!.id;
    final salt = _generateSalt();
    final hash = _hashPin(pin: pin, saltB64: salt, iterations: _pinIterations);
    await client.from('user_settings').upsert({
      'user_id': uid,
      'app_pin_hash': hash,
      'app_pin_salt': salt,
      'app_pin_iterations': _pinIterations,
    }, onConflict: 'user_id');
  }

  /// Change the PIN. Verifies [currentPin] matches the stored hash, then
  /// stores a fresh salt + hash for [newPin].
  Future<bool> changePin({
    required String currentPin,
    required String newPin,
  }) async {
    final ok = await verifyPin(currentPin);
    if (!ok) return false;
    await setPin(newPin);
    return true;
  }

  /// Verify a PIN attempt against the stored hash. Returns false when no PIN
  /// has been set yet.
  Future<bool> verifyPin(String pin) async {
    final row = await mySettings();
    if (row == null) return false;
    final hash = row['app_pin_hash'] as String?;
    final salt = row['app_pin_salt'] as String?;
    final iter = (row['app_pin_iterations'] as int?) ?? _pinIterations;
    if (hash == null || salt == null) return false;
    final computed = _hashPin(pin: pin, saltB64: salt, iterations: iter);
    return _constantTimeEquals(computed, hash);
  }

  /// Clear the PIN — used when the user disables app-PIN entirely.
  Future<void> clearPin() async {
    final client = ArlSupabase.requireClient();
    final uid = client.auth.currentUser!.id;
    await client.from('user_settings').upsert({
      'user_id': uid,
      'app_pin_hash': null,
      'app_pin_salt': null,
      'app_pin_iterations': null,
    }, onConflict: 'user_id');
  }

  String _generateSalt() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(_saltBytes, (_) => rnd.nextInt(256));
    return base64.encode(bytes);
  }

  String _hashPin({
    required String pin,
    required String saltB64,
    required int iterations,
  }) {
    final salt = base64.decode(saltB64);
    var current = <int>[...salt, ...utf8.encode(pin)];
    for (var i = 0; i < iterations; i++) {
      current = sha256.convert(current).bytes;
    }
    return base64.encode(current);
  }

  bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
