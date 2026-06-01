import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth/error_codes.dart' as auth_errors;

/// Snapshot of the per-device app-lock configuration.
class AppLockSettings {
  /// User has opted in to biometric unlock on this device.
  final bool biometricEnabled;

  /// User has opted in to PIN unlock on this device. Forced to true while a
  /// PIN hash exists but biometric is disabled, so the lock screen never
  /// strands the user with no way in.
  final bool pinRequired;

  /// True when a PIN hash + salt are stored locally.
  final bool hasPin;

  const AppLockSettings({
    required this.biometricEnabled,
    required this.pinRequired,
    required this.hasPin,
  });

  static const empty = AppLockSettings(
    biometricEnabled: false,
    pinRequired: false,
    hasPin: false,
  );

  /// True when any gate is active. Cold-launch / resume code consults this
  /// to decide whether to show the lock screen.
  bool get lockEnabled => biometricEnabled || pinRequired || hasPin;

  AppLockSettings copyWith({
    bool? biometricEnabled,
    bool? pinRequired,
    bool? hasPin,
  }) {
    return AppLockSettings(
      biometricEnabled: biometricEnabled ?? this.biometricEnabled,
      pinRequired: pinRequired ?? this.pinRequired,
      hasPin: hasPin ?? this.hasPin,
    );
  }
}

/// Per-device app-lock state + PIN store.
///
/// All material lives in flutter_secure_storage (Keychain on iOS, EncryptedSharedPreferences
/// on Android, IndexedDB-backed on web). The PIN is never persisted in plaintext —
/// what's stored is sha256(salt + pin) iterated 100k times, alongside the random
/// salt and the iteration count.
///
/// Note: server also stores a PIN hash in `user_settings.app_pin_hash` (via
/// UserSettingsRepository) for the SecurityScreen's "Change PIN" flow. The
/// runtime lock screen, however, verifies against the LOCAL store — it must
/// work fully offline, including cold launch before any network call.
class AppLockService {
  static const _kBiometricEnabled = 'arl.lock.biometric_enabled';
  static const _kPinRequired = 'arl.lock.pin_required';
  static const _kPinHash = 'arl.lock.pin_hash';
  static const _kPinSalt = 'arl.lock.pin_salt';
  static const _kPinIterations = 'arl.lock.pin_iterations';

  static const int _pinIterations = 100000;
  static const int _saltBytes = 16;

  /// Grace period after backgrounding before a fresh unlock is required.
  /// Short enough that an unattended phone re-locks quickly, long enough
  /// that briefly switching to a notification or the camera doesn't
  /// nag the user.
  static const Duration resumeGrace = Duration(seconds: 30);

  /// flutter_secure_storage. AndroidOptions tells it to use
  /// EncryptedSharedPreferences (which survives backups + has a stable
  /// API surface). iOS / web defaults are fine.
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static final _auth = LocalAuthentication();

  Future<AppLockSettings> read() async {
    final biometric = await _storage.read(key: _kBiometricEnabled);
    final pinReq = await _storage.read(key: _kPinRequired);
    final hash = await _storage.read(key: _kPinHash);
    return AppLockSettings(
      biometricEnabled: biometric == 'true',
      pinRequired: pinReq == 'true',
      hasPin: hash != null && hash.isNotEmpty,
    );
  }

  Future<void> setBiometricEnabled(bool value) async {
    await _storage.write(key: _kBiometricEnabled, value: value ? 'true' : 'false');
  }

  Future<void> setPinRequired(bool value) async {
    await _storage.write(key: _kPinRequired, value: value ? 'true' : 'false');
  }

  /// Store a fresh PIN. Generates a random salt and persists
  /// sha256(salt + pin) iterated [_pinIterations] times.
  Future<void> setPin(String pin) async {
    final salt = _generateSalt();
    final hash = _hashPin(pin: pin, saltB64: salt, iterations: _pinIterations);
    await _storage.write(key: _kPinSalt, value: salt);
    await _storage.write(key: _kPinHash, value: hash);
    await _storage.write(key: _kPinIterations, value: '$_pinIterations');
  }

  /// Verify [pin] against the stored hash. Returns false when no PIN is set
  /// or when the digest doesn't match.
  Future<bool> verifyPin(String pin) async {
    final hash = await _storage.read(key: _kPinHash);
    final salt = await _storage.read(key: _kPinSalt);
    final iterStr = await _storage.read(key: _kPinIterations);
    if (hash == null || salt == null) return false;
    final iterations = int.tryParse(iterStr ?? '') ?? _pinIterations;
    final computed = _hashPin(pin: pin, saltB64: salt, iterations: iterations);
    return _constantTimeEquals(computed, hash);
  }

  /// Drop the PIN material. Also flips `pinRequired` off — a required PIN
  /// with no stored hash would lock the user out permanently.
  Future<void> clearPin() async {
    await _storage.delete(key: _kPinHash);
    await _storage.delete(key: _kPinSalt);
    await _storage.delete(key: _kPinIterations);
    await _storage.write(key: _kPinRequired, value: 'false');
  }

  /// Wipe everything — called on sign-out so a different account can't
  /// inherit the previous user's PIN.
  Future<void> clearAll() async {
    await _storage.delete(key: _kBiometricEnabled);
    await _storage.delete(key: _kPinRequired);
    await _storage.delete(key: _kPinHash);
    await _storage.delete(key: _kPinSalt);
    await _storage.delete(key: _kPinIterations);
  }

  /// True when the device can prompt for biometrics. Always false on web —
  /// local_auth's web support is unreliable and would mislead the user
  /// into enabling a toggle that does nothing.
  Future<bool> biometricAvailable() async {
    if (kIsWeb) return false;
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final supported = await _auth.isDeviceSupported();
      return canCheck || supported;
    } on PlatformException catch (e) {
      if (kDebugMode) {
        debugPrint('[AppLock] biometricAvailable PlatformException: '
            '${e.code} ${e.message}');
      }
      return false;
    } catch (e) {
      if (kDebugMode) debugPrint('[AppLock] biometricAvailable error: $e');
      return false;
    }
  }

  /// True when the device has at least one biometric enrolled. Used to
  /// surface the "enroll a fingerprint" hint if the toggle is on but the
  /// OS has nothing to match against.
  Future<bool> biometricEnrolled() async {
    if (kIsWeb) return false;
    try {
      final available = await _auth.getAvailableBiometrics();
      if (kDebugMode) {
        debugPrint('[AppLock] getAvailableBiometrics: $available');
      }
      return available.isNotEmpty;
    } on PlatformException catch (e) {
      if (kDebugMode) {
        debugPrint('[AppLock] biometricEnrolled PlatformException: '
            '${e.code} ${e.message}');
      }
      return false;
    } catch (e) {
      if (kDebugMode) debugPrint('[AppLock] biometricEnrolled error: $e');
      return false;
    }
  }

  /// Prompt the OS biometric / device-credential sheet. We allow device
  /// passcode fallback (`biometricOnly: false`) deliberately: a user with
  /// a partial sensor reading shouldn't be forced through PIN entry when
  /// the OS itself can authenticate them.
  ///
  /// Returns false on any error. PlatformException details are logged in
  /// debug mode so silent failures (e.g. `no_fragment_activity` when the
  /// host Activity isn't a FragmentActivity, or `NotAvailable` when the
  /// device has no hardware) are visible in `flutter logs` rather than
  /// just presenting as "biometric not recognised" to the user.
  Future<bool> authenticateBiometric({String? reason}) async {
    if (kIsWeb) return false;
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason ?? 'Unlock Growize',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
      if (kDebugMode) {
        debugPrint('[AppLock] authenticate -> $ok');
      }
      return ok;
    } on PlatformException catch (e) {
      if (kDebugMode) {
        debugPrint(
            '[AppLock] authenticate PlatformException: ${e.code} ${e.message}');
      }
      // Distinguish the known recoverable errors so callers can decide
      // how to surface them. For now we still collapse to a single bool
      // — the LockScreen reads service state separately to render hints.
      // Listing the codes here keeps the intent explicit.
      switch (e.code) {
        case auth_errors.notAvailable:
        case auth_errors.notEnrolled:
        case auth_errors.lockedOut:
        case auth_errors.permanentlyLockedOut:
        case auth_errors.passcodeNotSet:
        case auth_errors.otherOperatingSystem:
          return false;
        default:
          return false;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[AppLock] authenticate error: $e');
      return false;
    }
  }

  // ── PIN hashing helpers ───────────────────────────────────────────────

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
