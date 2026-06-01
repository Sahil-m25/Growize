import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_lock_service.dart';

/// Thrown by [AppLockController.setBiometricEnabled] when the caller tries to
/// switch biometric ON without a PIN in place. The PIN is the only offline
/// rescue path when the biometric stops working (sensor failure, fingerprint
/// removed in OS settings, swapping to a device without biometric, web).
/// Without it the user would be locked out of the app permanently on
/// next launch.
class BiometricRequiresPinException implements Exception {
  const BiometricRequiresPinException();
  @override
  String toString() =>
      'Set an app PIN first — it is required as a fallback for biometric unlock.';
}

/// Thrown by [AppLockController.setBiometricEnabled] when the caller tries to
/// enable biometric on a platform that does not support it (currently any
/// kIsWeb build). Surfaces the same way as the missing-PIN case so the UI
/// can render a single coherent error.
class BiometricUnsupportedException implements Exception {
  const BiometricUnsupportedException();
  @override
  String toString() => 'Biometric unlock is not supported on this device.';
}

/// Single service instance — flutter_secure_storage is itself stateless so
/// this is just to share one across providers.
final appLockServiceProvider = Provider<AppLockService>((_) => AppLockService());

/// Current per-device lock configuration. Reads from secure storage on first
/// build; mutations should go through [AppLockController] which invalidates
/// this provider when persisted state changes.
final appLockSettingsProvider = FutureProvider<AppLockSettings>((ref) async {
  final svc = ref.watch(appLockServiceProvider);
  return svc.read();
});

/// Runtime "is the app currently locked?" flag.
///
/// Lifecycle:
/// - Defaults to true so cold launch can decide based on actual settings
///   without flashing protected content first. The root widget reads
///   [appLockSettingsProvider] right after boot — if no lock is configured
///   it flips this to false immediately.
/// - WidgetsBindingObserver in the root sets it to true after a
///   foregrounding event when the grace period has elapsed.
/// - The lock screen flips it back to false on successful authentication.
final appLockedProvider = StateProvider<bool>((ref) => true);

/// Timestamp of the most recent backgrounding event. Used to decide whether
/// a resume should re-lock or not.
final lastBackgroundedAtProvider = StateProvider<DateTime?>((ref) => null);

/// Helper class — provides a stable API for screens to mutate lock settings
/// without each consumer having to invalidate the FutureProvider by hand.
class AppLockController {
  final Ref _ref;
  AppLockController(this._ref);

  AppLockService get _svc => _ref.read(appLockServiceProvider);

  Future<AppLockSettings> current() => _svc.read();

  /// Persist the biometric-unlock preference.
  ///
  /// Enabling (value == true) is only allowed when:
  ///   - the device platform actually supports biometric auth
  ///     (web is always rejected — local_auth's web support is unreliable);
  ///   - a PIN is set as an offline rescue path. Without the PIN, a future
  ///     biometric failure (sensor disabled, fingerprint removed, app
  ///     re-installed on a device with no enrolled biometric) would lock
  ///     the user out with no way back in.
  ///
  /// Throws [BiometricUnsupportedException] / [BiometricRequiresPinException]
  /// on enforcement violation. Disabling is always allowed.
  Future<void> setBiometricEnabled(bool value) async {
    if (value) {
      final supported = await _svc.biometricAvailable();
      if (!supported) {
        throw const BiometricUnsupportedException();
      }
      final settings = await _svc.read();
      if (!settings.hasPin) {
        throw const BiometricRequiresPinException();
      }
    }
    await _svc.setBiometricEnabled(value);
    _ref.invalidate(appLockSettingsProvider);
  }

  Future<void> setPinRequired(bool value) async {
    await _svc.setPinRequired(value);
    _ref.invalidate(appLockSettingsProvider);
  }

  Future<void> setPin(String pin) async {
    await _svc.setPin(pin);
    // Requiring the PIN as soon as it's set is the least-surprising default;
    // the user just took the action because they wanted gating.
    await _svc.setPinRequired(true);
    _ref.invalidate(appLockSettingsProvider);
  }

  Future<bool> verifyPin(String pin) => _svc.verifyPin(pin);

  Future<void> clearPin() async {
    await _svc.clearPin();
    _ref.invalidate(appLockSettingsProvider);
  }

  Future<void> clearAll() async {
    await _svc.clearAll();
    _ref.invalidate(appLockSettingsProvider);
  }

  Future<bool> biometricAvailable() => _svc.biometricAvailable();
  Future<bool> biometricEnrolled() => _svc.biometricEnrolled();
  Future<bool> authenticateBiometric({String? reason}) =>
      _svc.authenticateBiometric(reason: reason);

  /// Mark the app as locked. Called by the lifecycle observer in the root.
  void lock() {
    _ref.read(appLockedProvider.notifier).state = true;
  }

  /// Mark the app as unlocked — invoked by [LockScreen] after a successful
  /// biometric or PIN check.
  void unlock() {
    _ref.read(appLockedProvider.notifier).state = false;
    _ref.read(lastBackgroundedAtProvider.notifier).state = null;
  }

  /// Record that the app went to the background.
  void noteBackgrounded() {
    _ref.read(lastBackgroundedAtProvider.notifier).state = DateTime.now();
  }

  /// Returns true when enough time has elapsed since the last backgrounding
  /// to justify a fresh unlock prompt.
  bool shouldChallengeOnResume() {
    final at = _ref.read(lastBackgroundedAtProvider);
    if (at == null) return false;
    return DateTime.now().difference(at) >= AppLockService.resumeGrace;
  }
}

final appLockControllerProvider = Provider<AppLockController>(
  (ref) => AppLockController(ref),
);

/// Convenience — boots the lock state from persisted settings on first read.
///
/// Returns the resolved [AppLockSettings] so the caller can decide what to
/// render. When no gate is configured, flips [appLockedProvider] to false
/// immediately; otherwise the lock screen takes over.
final lockBootProvider = FutureProvider<AppLockSettings>((ref) async {
  final settings = await ref.watch(appLockSettingsProvider.future);
  // Schedule the flip outside the build phase so we don't mutate state
  // mid-build (which throws in Riverpod).
  if (!settings.lockEnabled) {
    Future<void>.microtask(() {
      ref.read(appLockedProvider.notifier).state = false;
    });
  }
  if (kDebugMode) {
    debugPrint(
      '[AppLock] boot — biometric=${settings.biometricEnabled} '
      'pinRequired=${settings.pinRequired} hasPin=${settings.hasPin}',
    );
  }
  return settings;
});
