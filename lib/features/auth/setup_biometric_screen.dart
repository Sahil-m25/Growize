import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:arl_app/core/auth/app_lock_provider.dart';
import 'package:arl_app/core/auth/secure_session_store.dart';
import 'package:arl_app/core/navigation/route_names.dart';
import 'package:arl_app/core/providers/repositories.dart';
import 'package:arl_app/core/supabase/supabase_client.dart';
import 'package:arl_app/core/theme/arl_colors.dart';

/// Post-login one-screen prompt — encourages the user to enable
/// biometric unlock right after they verify their OTP.
///
/// "Set up now" runs the same controller path the SecurityScreen
/// toggle uses (including the PIN fallback requirement). "Skip for
/// now" just goes home — the user can still enable biometric later
/// from Profile -> Security.
///
/// Web safety: local_auth has no working backend on the web build,
/// so we hide the primary CTA there and the screen acts as an
/// informational "go to Security on mobile" notice. In practice this
/// route is mostly hit on phone-form-factor builds because the lock
/// gate only kicks in there too.
class SetupBiometricScreen extends ConsumerStatefulWidget {
  const SetupBiometricScreen({super.key});

  @override
  ConsumerState<SetupBiometricScreen> createState() =>
      _SetupBiometricScreenState();
}

class _SetupBiometricScreenState extends ConsumerState<SetupBiometricScreen> {
  bool _busy = false;

  Future<void> _skip() async {
    if (!mounted) return;
    context.go(RouteNames.home);
  }

  Future<void> _setupNow() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final controller = ref.read(appLockControllerProvider);

    try {
      if (kIsWeb) {
        messenger.showSnackBar(const SnackBar(
          content: Text(
            'Biometric unlock is not supported on the web build. Use the mobile app.',
          ),
        ));
        return;
      }

      final available = await controller.biometricAvailable();
      if (!available) {
        messenger.showSnackBar(const SnackBar(
          content: Text(
            'Biometric authentication is not available on this device.',
          ),
        ));
        return;
      }
      final enrolled = await controller.biometricEnrolled();
      if (!enrolled) {
        messenger.showSnackBar(const SnackBar(
          content: Text(
            'No fingerprint or face is enrolled. Enroll one in your device settings, then try again.',
          ),
        ));
        return;
      }

      // PIN is the required offline fallback for biometric — without
      // it a sensor problem locks the user out. If no PIN is set,
      // prompt for one in the same modal dance SecurityScreen uses.
      final settings = await controller.current();
      if (!settings.hasPin) {
        final pin = await _promptNewPin();
        if (pin == null) {
          // User cancelled — leave them on this screen so they can
          // try again or skip explicitly.
          return;
        }
        await controller.setPin(pin);
        // Mirror to server (best-effort — local is source of truth).
        try {
          await ref.read(userSettingsRepositoryProvider).setPin(pin);
        } catch (_) {}
      }

      // Now run the actual biometric confirmation so we know the
      // sensor can recognise the user before we commit the setting.
      final ok = await controller.authenticateBiometric(
        reason: 'Confirm to enable biometric unlock',
      );
      if (!ok) {
        messenger.showSnackBar(const SnackBar(
          content: Text('Biometric check failed. Setting not changed.'),
        ));
        return;
      }

      await controller.setBiometricEnabled(true);
      // Mirror the server flag so the OTP screen post-login check
      // skips this nudge on future logins from any device.
      try {
        await ref
            .read(userSettingsRepositoryProvider)
            .updateToggles(biometricEnabled: true);
      } catch (_) {}
      // Keep the legacy SecureSessionStore flag in sync so the
      // existing biometric refresh-token path stays warm.
      final store = SecureSessionStore();
      final session = ArlSupabase.client?.auth.currentSession;
      final email = session?.user.email;
      final refresh = session?.refreshToken;
      if (email != null && refresh != null) {
        await store.saveSession(email: email, refreshToken: refresh);
      }
      await store.setBiometricEnabled(true);
      ref.invalidate(userSettingsProvider);

      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(
        content: Text('Biometric unlock enabled.'),
      ));
      context.go(RouteNames.home);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not enable biometric: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Prompt for a single PIN entry (4-6 digits). Returns null on cancel.
  Future<String?> _promptPin({required String title}) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(
          title,
          style: const TextStyle(
            color: ArlColors.charcoal,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            hintText: '4-6 digits',
            counterText: '',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final v = ctrl.text.trim();
              if (v.length < 4) return;
              Navigator.of(ctx).pop(v);
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  Future<String?> _promptNewPin() async {
    final pin = await _promptPin(title: 'Choose a PIN');
    if (pin == null) return null;
    if (!mounted) return null;
    final confirm = await _promptPin(title: 'Re-enter PIN');
    if (confirm == null) return null;
    if (pin != confirm) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PINs do not match.')),
        );
      }
      return null;
    }
    return pin;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ArlColors.cream,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(flex: 2),
              SizedBox(
                width: 96,
                height: 96,
                child: Image.asset(
                  'assets/images/growize_g.png',
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  isAntiAlias: true,
                ),
              ),
              const SizedBox(height: 28),
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: ArlColors.accent.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.fingerprint,
                  color: ArlColors.accent,
                  size: 40,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Set up biometric unlock',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: ArlColors.charcoal,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'Open Growize quickly with your fingerprint or face — '
                  'your data stays on this device.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: ArlColors.muted,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ),
              const Spacer(flex: 3),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _busy ? null : _setupNow,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ArlColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    elevation: 0,
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Set up now',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _busy ? null : _skip,
                child: const Text(
                  'Skip for now',
                  style: TextStyle(
                    color: ArlColors.muted,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'You can change this any time from Profile → Security.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: ArlColors.muted,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
