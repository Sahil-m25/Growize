import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:arl_app/core/auth/app_lock_provider.dart';
import 'package:arl_app/core/auth/app_lock_service.dart';
import 'package:arl_app/core/auth/session_manager.dart';
import 'package:arl_app/core/theme/arl_colors.dart';

/// Full-screen runtime lock gate.
///
/// Shown by the root widget when [appLockedProvider] is true and the user
/// has actually enabled a lock (biometric or PIN). Calls into
/// [AppLockController] to authenticate, then flips the lock state off so
/// the underlying app becomes visible again.
///
/// UX:
/// 1. If biometric is enabled and available, the OS sheet is prompted
///    automatically on first build.
/// 2. The 4-6 digit PIN pad is always visible as a fallback.
/// 3. Three consecutive wrong PINs triggers a 30-second cooldown rather
///    than logging the user out — private launch, no need for the harder
///    server-revocation path.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  final _pinCtrl = TextEditingController();
  bool _busy = false;
  bool _attemptedBiometric = false;
  String? _error;
  int _wrongAttempts = 0;
  DateTime? _cooldownUntil;

  /// True when the device actually supports biometrics. Distinct from
  /// `settings.biometricEnabled` (the user's opt-in). On web this is
  /// always false, so we degrade gracefully to PIN-only or the
  /// sign-out escape rather than dangling a fingerprint button that
  /// does nothing.
  bool _biometricSupported = false;
  bool _platformChecked = false;

  @override
  void initState() {
    super.initState();
    // Defer to the post-frame callback so the inherited widgets are ready
    // before we touch providers. We then wait a further 500 ms before
    // firing the biometric prompt — on some Android devices the OS sheet
    // races the LockScreen layout and either auto-cancels itself or
    // returns success before the UI is ready to consume it. The delay
    // gives the LockScreen time to mount completely.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _refreshPlatformSupport();
      if (!mounted) return;
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      await _maybePromptBiometric();
    });
  }

  Future<void> _refreshPlatformSupport() async {
    final controller = ref.read(appLockControllerProvider);
    final supported = await controller.biometricAvailable();
    if (!mounted) return;
    setState(() {
      _biometricSupported = supported;
      _platformChecked = true;
    });
  }

  @override
  void dispose() {
    _pinCtrl.dispose();
    super.dispose();
  }

  Future<void> _maybePromptBiometric() async {
    if (_attemptedBiometric) return;

    final settingsAsync = ref.read(appLockSettingsProvider);
    final settings = settingsAsync.asData?.value ?? AppLockSettings.empty;
    if (kDebugMode) {
      debugPrint('[LockScreen] _maybePromptBiometric: '
          'biometricEnabled=${settings.biometricEnabled} '
          'hasPin=${settings.hasPin}');
    }
    if (!settings.biometricEnabled) return;

    final controller = ref.read(appLockControllerProvider);
    final available = await controller.biometricAvailable();
    if (kDebugMode) {
      debugPrint('[LockScreen] biometricAvailable=$available');
    }
    if (!mounted) return;
    if (!available) {
      // Don't burn the one-shot attempt flag. The user may still be
      // able to unlock via PIN; biometric is unavailable on this
      // platform / device. Surface a hint when there's no PIN
      // alternative so they understand why nothing happened.
      if (!settings.hasPin) {
        setState(() {
          _error =
              'Fingerprint unlock is not available on this device. Sign out below to log back in.';
        });
      }
      return;
    }
    // Latch only once we know the OS will actually show the prompt —
    // prevents auto-cancel races on resume.
    _attemptedBiometric = true;

    final enrolled = await controller.biometricEnrolled();
    if (!enrolled) {
      setState(() {
        _error = settings.hasPin
            ? 'No fingerprint enrolled on this device. Use your PIN, or enroll a fingerprint in device settings.'
            : 'No fingerprint enrolled on this device. Enroll one in device settings and try again.';
      });
      return;
    }

    setState(() => _busy = true);
    final ok = await controller.authenticateBiometric(reason: 'Unlock Growize');
    if (!mounted) return;
    if (ok) {
      controller.unlock();
      return;
    }
    setState(() {
      _busy = false;
      _error = settings.hasPin
          ? 'Biometric not recognised. You can use your PIN instead.'
          : 'Biometric not recognised. Try again.';
    });
  }

  Future<void> _retryBiometric() async {
    _attemptedBiometric = false;
    await _maybePromptBiometric();
  }

  Future<void> _submitPin() async {
    if (_busy) return;
    if (_inCooldown) return;
    final pin = _pinCtrl.text.trim();
    if (pin.length < 4) {
      setState(() => _error = 'Enter your PIN (4-6 digits).');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final controller = ref.read(appLockControllerProvider);
    final ok = await controller.verifyPin(pin);
    if (!mounted) return;
    if (ok) {
      controller.unlock();
      return;
    }
    _wrongAttempts += 1;
    _pinCtrl.clear();
    if (_wrongAttempts >= 3) {
      _cooldownUntil = DateTime.now().add(const Duration(seconds: 30));
      setState(() {
        _busy = false;
        _error = 'Too many attempts. Try again in 30 seconds.';
      });
      _startCooldownTicker();
    } else {
      setState(() {
        _busy = false;
        _error = 'PIN incorrect. ${3 - _wrongAttempts} attempts remaining.';
      });
    }
  }

  bool get _inCooldown {
    final until = _cooldownUntil;
    if (until == null) return false;
    return DateTime.now().isBefore(until);
  }

  void _startCooldownTicker() {
    Future<void>.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      if (!_inCooldown) {
        setState(() {
          _wrongAttempts = 0;
          _cooldownUntil = null;
          _error = null;
        });
      } else {
        setState(() {});
        _startCooldownTicker();
      }
    });
  }

  Future<void> _signOutEscape() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await SessionManager.signOut();
    } catch (_) {
      // Swallow — the auth state listener clears local lock material on
      // signedOut; we still want to fall through to unlocking the gate
      // so the router can render the sign-in screen.
    }
    if (!mounted) return;
    ref.read(appLockControllerProvider).unlock();
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(appLockSettingsProvider);
    final settings = settingsAsync.asData?.value ?? AppLockSettings.empty;
    // Biometric button only shows when (a) user opted in, AND (b) the
    // platform actually supports biometric auth. On web this is always
    // false. Until the async platform check resolves, treat biometric
    // as unavailable so we don't briefly flash an unusable button.
    final canUseBiometric =
        settings.biometricEnabled && _biometricSupported && _platformChecked;
    final canUsePin = settings.hasPin;
    final noAuthAvailable = !canUseBiometric && !canUsePin;

    return Scaffold(
      backgroundColor: ArlColors.primary,
      body: SafeArea(
        child: SizedBox.expand(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: MediaQuery.of(context).size.height -
                    MediaQuery.of(context).padding.vertical -
                    48,
              ),
              child: IntrinsicHeight(
                child: Column(
                  mainAxisSize: MainAxisSize.max,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 32),
                    Center(
                      child: Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: ArlColors.gold.withValues(alpha: 0.45),
                            width: 1.5,
                          ),
                        ),
                        child: const Icon(
                          Icons.lock_outline,
                          color: ArlColors.gold,
                          size: 38,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Growize',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: ArlColors.gold,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 2,
                        fontFamily: 'Inter',
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'App is locked',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Inter',
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      canUseBiometric && canUsePin
                          ? 'Verify with fingerprint or PIN to continue.'
                          : canUseBiometric
                              ? 'Verify with fingerprint to continue.'
                              : canUsePin
                                  ? 'Enter your PIN to continue.'
                                  : 'Sign in again to continue.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 13,
                        fontFamily: 'Inter',
                      ),
                    ),
                    const SizedBox(height: 28),
                    if (canUseBiometric) ...[
                      _BiometricButton(
                        busy: _busy && _attemptedBiometric,
                        onTap: _busy ? null : _retryBiometric,
                      ),
                      const SizedBox(height: 18),
                      if (canUsePin)
                        Row(
                          children: [
                            Expanded(
                                child: Divider(
                                    color: Colors.white
                                        .withValues(alpha: 0.25))),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 10),
                              child: Text(
                                'or use PIN',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.6),
                                  fontSize: 11,
                                  fontFamily: 'Inter',
                                ),
                              ),
                            ),
                            Expanded(
                                child: Divider(
                                    color: Colors.white
                                        .withValues(alpha: 0.25))),
                          ],
                        ),
                      if (canUsePin) const SizedBox(height: 18),
                    ],
                    if (canUsePin)
                      _PinField(
                        controller: _pinCtrl,
                        enabled: !_inCooldown && !_busy,
                        onSubmitted: (_) => _submitPin(),
                      ),
                    if (canUsePin) ...[
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed:
                              (_busy || _inCooldown) ? null : _submitPin,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: ArlColors.gold,
                            foregroundColor: ArlColors.charcoal,
                            disabledBackgroundColor:
                                ArlColors.gold.withValues(alpha: 0.4),
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                            elevation: 0,
                          ),
                          child: _busy && !_attemptedBiometric
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: ArlColors.charcoal,
                                  ),
                                )
                              : const Text(
                                  'Unlock',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    fontFamily: 'Inter',
                                  ),
                                ),
                        ),
                      ),
                    ],
                    if (noAuthAvailable) ...[
                      const SizedBox(height: 12),
                      // Defensive fallback. Reached when:
                      //  - biometric was enabled but the device has no
                      //    enrolled biometric AND no PIN is set, OR
                      //  - on web with biometric enabled but local_auth
                      //    not supported AND no PIN, OR
                      //  - somehow the lock gate fires with no methods.
                      // The Sign-out escape below is always visible, so
                      // the user is never trapped.
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.15),
                          ),
                        ),
                        child: Text(
                          settings.biometricEnabled && !_biometricSupported
                              ? 'Fingerprint unlock is not available on this device. Sign out below to log back in.'
                              : 'No unlock method is configured. Sign out below to log back in.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 12,
                            fontFamily: 'Inter',
                          ),
                        ),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: ArlColors.earth.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: ArlColors.earth.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.info_outline,
                              color: ArlColors.gold,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _error!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontFamily: 'Inter',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    // Push the sign-out escape to the bottom of the
                    // viewport. Always visible — the user can never get
                    // stranded on this screen.
                    const Spacer(),
                    const SizedBox(height: 24),
                    TextButton(
                      onPressed: _busy ? null : _signOutEscape,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(
                        'Sign out and log back in',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          decoration: TextDecoration.underline,
                          decorationColor:
                              Colors.white.withValues(alpha: 0.4),
                          fontFamily: 'Inter',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BiometricButton extends StatelessWidget {
  final bool busy;
  final VoidCallback? onTap;
  const _BiometricButton({required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: ArlColors.gold.withValues(alpha: 0.55),
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (busy)
              const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: ArlColors.gold,
                ),
              )
            else
              const Icon(Icons.fingerprint, color: ArlColors.gold, size: 22),
            const SizedBox(width: 12),
            const Text(
              'Use biometric',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                fontFamily: 'Inter',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PinField extends StatelessWidget {
  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<String>? onSubmitted;
  const _PinField({
    required this.controller,
    required this.enabled,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      autofocus: true,
      obscureText: true,
      keyboardType: TextInputType.number,
      maxLength: 6,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onSubmitted: onSubmitted,
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 22,
        fontWeight: FontWeight.w600,
        letterSpacing: 8,
        fontFamily: 'Inter',
      ),
      decoration: InputDecoration(
        counterText: '',
        hintText: '••••',
        hintStyle: TextStyle(
          color: Colors.white.withValues(alpha: 0.35),
          letterSpacing: 8,
          fontSize: 22,
        ),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.08),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: ArlColors.gold, width: 1.4),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
        ),
      ),
    );
  }
}
