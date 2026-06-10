import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:arl_app/core/auth/app_lock_provider.dart';
import 'package:arl_app/core/auth/app_lock_service.dart';
import 'package:arl_app/core/auth/secure_session_store.dart';
import 'package:arl_app/core/navigation/route_names.dart';
import 'package:arl_app/core/providers/repositories.dart';
import 'package:arl_app/core/supabase/supabase_client.dart';
import 'package:arl_app/core/theme/arl_colors.dart';
import 'package:arl_app/features/legal/legal_content.dart';

/// Latest marketing-consent state for the signed-in user. Backed by the
/// append-only `consents` audit log. Re-read after each toggle.
final marketingConsentProvider = FutureProvider.autoDispose<bool>((ref) async {
  return ref.read(userSettingsRepositoryProvider).marketingConsentGranted();
});

/// Profile → Security screen.
///
/// Surfaces three real toggles:
///   • Biometric unlock — gates app launch / resume with the OS biometric
///     prompt. Backed by [AppLockService] on-device + a mirror on the
///     server (`user_settings.biometric_enabled`) for cross-device hints.
///   • Require PIN — when on, app launch / resume requires the local PIN.
///     Disabled until a PIN is actually set.
///   • Set / Change / Remove PIN — writes a salted 100k-iter sha256 hash
///     to flutter_secure_storage (and mirrors the hash to the server for
///     parity with the legacy "change PIN" flow).
class SecurityScreen extends ConsumerWidget {
  const SecurityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(userSettingsProvider);
    final lockSettingsAsync = ref.watch(appLockSettingsProvider);
    final loginsAsync = ref.watch(myLoginEventsProvider);
    final marketingGranted =
        ref.watch(marketingConsentProvider).asData?.value ?? false;

    return Scaffold(
      backgroundColor: ArlColors.cream,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: ArlColors.charcoal),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(RouteNames.home);
            }
          },
        ),
        title: const Text(
          'Security',
          style: TextStyle(
            color: ArlColors.charcoal,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: false,
      ),
      body: settingsAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: ArlColors.accent)),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Could not load security settings.\n$e',
              textAlign: TextAlign.center,
              style: const TextStyle(color: ArlColors.muted),
            ),
          ),
        ),
        data: (settings) {
          final lock = lockSettingsAsync.asData?.value ?? AppLockSettings.empty;
          final notificationsEnabled =
              (settings?['notifications_enabled'] as bool?) ?? true;
          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle('Authentication'),
                  Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: ArlColors.sand, width: 1),
                    ),
                    child: Column(
                      children: [
                        // Biometric unlock row is platform-gated. On the web
                        // build local_auth has no working backend, so the
                        // toggle would be a dead control — hide the row
                        // entirely rather than offering something that can't
                        // succeed. The row is also disabled (greyed) until a
                        // PIN is set, because the PIN is the only fallback
                        // when biometric stops working.
                        if (!kIsWeb) ...[
                          _SecurityRow(
                            icon: Icons.fingerprint,
                            iconColor: ArlColors.accent,
                            iconBg: ArlColors.accent.withOpacity(0.15),
                            title: 'Biometric unlock',
                            subtitle: lock.biometricEnabled
                                ? 'On — required to open the app'
                                : !lock.hasPin
                                    ? 'Set a PIN first to enable'
                                    : 'Off',
                            // Disabling is always allowed (escape hatch even
                            // if the user got into a no-PIN-but-biometric-on
                            // state in an earlier build). Enabling requires
                            // a PIN as fallback — the row disables the
                            // "enable" path by funnelling through
                            // [_setBiometric], which surfaces the right
                            // snackbar when hasPin is false.
                            trailing: Switch(
                              value: lock.biometricEnabled,
                              onChanged: (lock.biometricEnabled || lock.hasPin)
                                  ? (v) => _setBiometric(context, ref, v)
                                  : null,
                              thumbColor: WidgetStateProperty.resolveWith((s) =>
                                  s.contains(WidgetState.selected)
                                      ? ArlColors.accent
                                      : ArlColors.muted),
                            ),
                          ),
                          const Divider(
                              height: 1, color: ArlColors.sand, thickness: 1),
                        ],
                        _SecurityRow(
                          icon: Icons.password,
                          iconColor: ArlColors.primary,
                          iconBg: ArlColors.primary.withOpacity(0.1),
                          title: 'Require PIN',
                          subtitle: !lock.hasPin
                              ? 'Set a PIN first to enable'
                              : lock.pinRequired
                                  ? 'On — required to open the app'
                                  : 'Off',
                          trailing: Switch(
                            value: lock.pinRequired,
                            onChanged: !lock.hasPin
                                ? null
                                : (v) => _setPinRequired(context, ref, v),
                            thumbColor: WidgetStateProperty.resolveWith((s) =>
                                s.contains(WidgetState.selected)
                                    ? ArlColors.primary
                                    : ArlColors.muted),
                          ),
                        ),
                        const Divider(
                            height: 1, color: ArlColors.sand, thickness: 1),
                        _SecurityRow(
                          icon: Icons.smartphone,
                          iconColor: ArlColors.primary,
                          iconBg: ArlColors.primary.withOpacity(0.1),
                          title: lock.hasPin ? 'App PIN' : 'Set App PIN',
                          subtitle: lock.hasPin ? 'Set' : 'Not set',
                          onTap: () =>
                              _openPinFlow(context, ref, lock.hasPin),
                          trailing: const Icon(Icons.chevron_right,
                              color: ArlColors.primary, size: 18),
                        ),
                        const Divider(
                            height: 1, color: ArlColors.sand, thickness: 1),
                        _SecurityRow(
                          icon: Icons.notifications_outlined,
                          iconColor: ArlColors.gold,
                          iconBg: ArlColors.gold.withOpacity(0.15),
                          title: 'Notifications',
                          subtitle: notificationsEnabled ? 'On' : 'Off',
                          trailing: Switch(
                            value: notificationsEnabled,
                            onChanged: (v) =>
                                _setNotifications(context, ref, v),
                            thumbColor: WidgetStateProperty.resolveWith((s) =>
                                s.contains(WidgetState.selected)
                                    ? ArlColors.gold
                                    : ArlColors.muted),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (lock.lockEnabled)
                    Container(
                      margin: const EdgeInsets.only(bottom: 20),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: ArlColors.gold.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: ArlColors.gold.withOpacity(0.35),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.shield_outlined,
                              color: ArlColors.gold, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              lock.biometricEnabled && lock.pinRequired
                                  ? 'You will be asked to verify with biometrics or PIN every time you open Growize or return after 30 seconds.'
                                  : lock.biometricEnabled
                                      ? 'You will be asked to verify with biometrics every time you open Growize or return after 30 seconds.'
                                      : 'You will be asked to enter your PIN every time you open Growize or return after 30 seconds.',
                              style: const TextStyle(
                                color: ArlColors.charcoal,
                                fontSize: 11.5,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  _sectionTitle('Privacy & Consent'),
                  Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: ArlColors.sand, width: 1),
                    ),
                    child: Column(
                      children: [
                        _SecurityRow(
                          icon: Icons.campaign_outlined,
                          iconColor: ArlColors.accent,
                          iconBg: ArlColors.accent.withOpacity(0.15),
                          title: 'Product updates & offers',
                          subtitle: marketingGranted
                              ? 'On — optional marketing messages'
                              : 'Off — you only get essential service messages',
                          trailing: Switch(
                            value: marketingGranted,
                            onChanged: (v) => _setMarketing(context, ref, v),
                            thumbColor: WidgetStateProperty.resolveWith((s) =>
                                s.contains(WidgetState.selected)
                                    ? ArlColors.accent
                                    : ArlColors.muted),
                          ),
                        ),
                        const Divider(
                            height: 1, color: ArlColors.sand, thickness: 1),
                        _SecurityRow(
                          icon: Icons.manage_accounts_outlined,
                          iconColor: ArlColors.accent,
                          iconBg: ArlColors.accent.withOpacity(0.15),
                          title: 'Manage my data & rights',
                          subtitle:
                              'Download your data, set a nominee, request erasure',
                          onTap: () => context.push(RouteNames.privacyCenter),
                          trailing: const Icon(Icons.chevron_right,
                              color: ArlColors.primary, size: 18),
                        ),
                        const Divider(
                            height: 1, color: ArlColors.sand, thickness: 1),
                        _SecurityRow(
                          icon: Icons.privacy_tip_outlined,
                          iconColor: ArlColors.primary,
                          iconBg: ArlColors.primary.withOpacity(0.1),
                          title: 'Privacy Notice',
                          subtitle: 'What we collect, why, and your rights',
                          onTap: () => context.push(RouteNames.privacy),
                          trailing: const Icon(Icons.chevron_right,
                              color: ArlColors.primary, size: 18),
                        ),
                        const Divider(
                            height: 1, color: ArlColors.sand, thickness: 1),
                        _SecurityRow(
                          icon: Icons.description_outlined,
                          iconColor: ArlColors.primary,
                          iconBg: ArlColors.primary.withOpacity(0.1),
                          title: 'Terms of Service',
                          subtitle: 'The agreement governing your use',
                          onTap: () => context.push(RouteNames.terms),
                          trailing: const Icon(Icons.chevron_right,
                              color: ArlColors.primary, size: 18),
                        ),
                      ],
                    ),
                  ),
                  _sectionTitle('Login History'),
                  Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: ArlColors.sand, width: 1),
                    ),
                    child: loginsAsync.when(
                      loading: () => const SizedBox(
                        height: 32,
                        child: Center(
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: ArlColors.accent),
                          ),
                        ),
                      ),
                      error: (_, __) => const Text(
                        'Could not load login history.',
                        style: TextStyle(color: ArlColors.muted, fontSize: 12),
                      ),
                      data: (events) => events.isEmpty
                          ? const Row(
                              children: [
                                Icon(Icons.history,
                                    color: ArlColors.muted, size: 20),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'No login activity yet.',
                                    style: TextStyle(
                                      color: ArlColors.muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              children: [
                                for (var i = 0; i < events.length; i++) ...[
                                  if (i > 0)
                                    const Padding(
                                      padding:
                                          EdgeInsets.symmetric(vertical: 8),
                                      child: Divider(
                                          height: 1,
                                          color: ArlColors.sand,
                                          thickness: 1),
                                    ),
                                  _LoginRow(event: events[i]),
                                ],
                              ],
                            ),
                    ),
                  ),
                  _sectionTitle('Session'),
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: ArlColors.sand, width: 1),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Auto-lock on background',
                          style: TextStyle(
                            color: ArlColors.charcoal,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          '30 seconds',
                          style: TextStyle(
                            color: ArlColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: ArlColors.sand, width: 1),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Last login',
                              style: TextStyle(
                                color: ArlColors.charcoal,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _lastLoginText(loginsAsync.value),
                              style: const TextStyle(
                                color: ArlColors.muted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  _sectionTitle('App'),
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: ArlColors.sand, width: 1),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'App version',
                          style: TextStyle(
                            color: ArlColors.charcoal,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          '1.0.0 (Build 1)',
                          style: TextStyle(
                            color: ArlColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: ArlColors.sand, width: 1),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Privacy Policy',
                          style: TextStyle(
                            color: ArlColors.charcoal,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Icon(
                          Icons.open_in_new_outlined,
                          color: ArlColors.primary,
                          size: 16,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _setBiometric(
      BuildContext context, WidgetRef ref, bool value) async {
    final messenger = ScaffoldMessenger.of(context);
    final controller = ref.read(appLockControllerProvider);

    if (value) {
      // Web has no working local_auth backend — short-circuit before we
      // touch the platform layer. (The row itself is hidden on web, but
      // belt-and-suspenders.)
      if (kIsWeb) {
        messenger.showSnackBar(const SnackBar(
          content: Text(
            'Biometric unlock is not supported on the web build. Use the mobile app.',
          ),
        ));
        return;
      }
      // PIN must already be set so the user has a fallback if biometric
      // ever fails. Without it a sensor problem or fingerprint removal
      // would lock them out permanently. (Row UI also enforces this by
      // disabling the switch — defensive double-check here in case the
      // call comes from a different path.)
      final current = await controller.current();
      if (!current.hasPin) {
        messenger.showSnackBar(const SnackBar(
          content: Text(
            'Set an app PIN first — it is required as a fallback for biometric unlock.',
          ),
        ));
        return;
      }
      // Enabling biometric requires a successful biometric check first
      // so the user proves their identity before the gate goes live.
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
      final ok = await controller.authenticateBiometric(
        reason: 'Confirm to enable biometric unlock',
      );
      if (!ok) {
        messenger.showSnackBar(const SnackBar(
          content: Text('Biometric check failed. Setting not changed.'),
        ));
        return;
      }
    }

    try {
      // Local — drives the lock-screen behaviour on this device.
      await controller.setBiometricEnabled(value);
      // Server mirror — purely informational so the login screen can
      // hint "use biometric" without round-tripping the device.
      await ref
          .read(userSettingsRepositoryProvider)
          .updateToggles(biometricEnabled: value);
      // Keep the legacy SecureSessionStore flag in sync so the existing
      // login-screen biometric shortcut continues to work.
      final store = SecureSessionStore();
      if (value) {
        final session = ArlSupabase.client?.auth.currentSession;
        final email = session?.user.email;
        final refresh = session?.refreshToken;
        if (email != null && refresh != null) {
          await store.saveSession(email: email, refreshToken: refresh);
        }
        await store.setBiometricEnabled(true);
      } else {
        await store.clearBiometric();
      }
      ref.invalidate(userSettingsProvider);
    } on BiometricRequiresPinException catch (e) {
      // Should be unreachable because of the up-front guards, but the
      // controller throws this defensively too — surface its message
      // cleanly rather than as a raw "Could not save".
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    } on BiometricUnsupportedException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not save: $e')),
      );
    }
  }

  Future<void> _setPinRequired(
      BuildContext context, WidgetRef ref, bool value) async {
    final messenger = ScaffoldMessenger.of(context);
    final controller = ref.read(appLockControllerProvider);
    // Turning off "Require PIN" doesn't need a fresh check — the user
    // is already inside the app. Turning on without a PIN set would
    // lock them out; the row guards against that by disabling the
    // switch, but double-check defensively.
    final current = await controller.current();
    if (value && !current.hasPin) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Set a PIN first, then enable this.'),
      ));
      return;
    }
    try {
      await controller.setPinRequired(value);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  Future<void> _setMarketing(
      BuildContext context, WidgetRef ref, bool value) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      // Each grant/withdrawal appends a row to the consent audit log.
      await ref.read(userSettingsRepositoryProvider).setMarketingConsent(
            granted: value,
            docVersion: LegalDocs.version,
          );
      ref.invalidate(marketingConsentProvider);
      messenger.showSnackBar(SnackBar(
        content: Text(value
            ? 'Product updates turned on.'
            : 'Product updates turned off. You can re-enable this anytime.'),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  Future<void> _setNotifications(
      BuildContext context, WidgetRef ref, bool value) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(userSettingsRepositoryProvider)
          .updateToggles(notificationsEnabled: value);
      ref.invalidate(userSettingsProvider);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not save: $e')),
      );
    }
  }

  Future<void> _openPinFlow(
      BuildContext context, WidgetRef ref, bool pinSet) async {
    final action = pinSet
        ? await showModalBottomSheet<_PinAction>(
            context: context,
            backgroundColor: Colors.white,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            builder: (ctx) => _PinActionSheet(),
          )
        : _PinAction.set;
    if (action == null || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(userSettingsRepositoryProvider);
    final controller = ref.read(appLockControllerProvider);

    switch (action) {
      case _PinAction.set:
        final pin = await _promptNewPin(context);
        if (pin == null) return;
        try {
          // Local first — the on-device PIN is what gates the lock screen.
          await controller.setPin(pin);
          // Server mirror — kept so the legacy "change PIN" change flow
          // on other devices can still verify against a known hash.
          await repo.setPin(pin);
          ref.invalidate(userSettingsProvider);
          messenger.showSnackBar(const SnackBar(
            content: Text('PIN set. App will now require it on launch.'),
          ));
        } catch (e) {
          messenger.showSnackBar(
              SnackBar(content: Text('Could not set PIN: $e')));
        }
        return;
      case _PinAction.change:
        final current = await _promptPin(context, title: 'Enter current PIN');
        if (current == null) return;
        final ok = await controller.verifyPin(current);
        if (!ok) {
          messenger.showSnackBar(
              const SnackBar(content: Text('Current PIN incorrect.')));
          return;
        }
        if (!context.mounted) return;
        final next = await _promptNewPin(context);
        if (next == null) return;
        try {
          await controller.setPin(next);
          await repo.setPin(next);
          ref.invalidate(userSettingsProvider);
          messenger.showSnackBar(const SnackBar(content: Text('PIN updated.')));
        } catch (e) {
          messenger.showSnackBar(
              SnackBar(content: Text('Could not change PIN: $e')));
        }
        return;
      case _PinAction.remove:
        final current = await _promptPin(context, title: 'Enter current PIN');
        if (current == null) return;
        final ok = await controller.verifyPin(current);
        if (!ok) {
          messenger.showSnackBar(
              const SnackBar(content: Text('Current PIN incorrect.')));
          return;
        }
        await controller.clearPin();
        try {
          await repo.clearPin();
        } catch (_) {
          // Server clear is best-effort — local state is the source of truth
          // for the lock gate.
        }
        ref.invalidate(userSettingsProvider);
        messenger.showSnackBar(const SnackBar(content: Text('PIN removed.')));
        return;
    }
  }

  /// Prompt for a single PIN entry (4-6 digits). Returns null on cancel.
  Future<String?> _promptPin(BuildContext context, {required String title}) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(title,
            style: const TextStyle(
                color: ArlColors.charcoal,
                fontSize: 15,
                fontWeight: FontWeight.w600)),
        content: TextField(
          controller: controller,
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
              child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final v = controller.text.trim();
              if (v.length < 4) return;
              Navigator.of(ctx).pop(v);
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  /// Prompt for new PIN with confirmation. Returns null on cancel or mismatch.
  Future<String?> _promptNewPin(BuildContext context) async {
    final pin = await _promptPin(context, title: 'Choose a new PIN');
    if (pin == null) return null;
    if (!context.mounted) return null;
    final confirm = await _promptPin(context, title: 'Re-enter PIN');
    if (confirm == null) return null;
    if (pin != confirm) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('PINs do not match.')));
      }
      return null;
    }
    return pin;
  }

  String _lastLoginText(List<Map<String, dynamic>>? events) {
    if (events == null || events.isEmpty) return 'No login activity yet.';
    final row = events.first;
    final occurred =
        DateTime.tryParse(row['occurred_at'] as String? ?? '')?.toLocal();
    final device = row['device_label'] as String? ?? 'Unknown device';
    if (occurred == null) return device;
    return '${DateFormat('MMM d, h:mm a').format(occurred)} · $device';
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: ArlColors.charcoal,
          fontSize: 13,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

enum _PinAction { set, change, remove }

class _PinActionSheet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit_outlined, color: ArlColors.primary),
            title: const Text('Change PIN'),
            onTap: () => Navigator.of(context).pop(_PinAction.change),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: ArlColors.earth),
            title: const Text('Remove PIN'),
            onTap: () => Navigator.of(context).pop(_PinAction.remove),
          ),
        ],
      ),
    );
  }
}

class _LoginRow extends StatelessWidget {
  final Map<String, dynamic> event;
  const _LoginRow({required this.event});

  @override
  Widget build(BuildContext context) {
    final occurred =
        DateTime.tryParse(event['occurred_at'] as String? ?? '')?.toLocal();
    final device = event['device_label'] as String? ?? 'Unknown device';
    final platform = event['platform'] as String? ?? '';
    final version = event['app_version'] as String? ?? '';
    final when =
        occurred == null ? '—' : DateFormat('MMM d, h:mm a').format(occurred);
    final detail = [
      if (platform.isNotEmpty) platform,
      if (version.isNotEmpty) 'v$version'
    ].join(' · ');
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: ArlColors.muted.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.history, color: ArlColors.muted, size: 16),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$when · $device',
                style: const TextStyle(
                  color: ArlColors.charcoal,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (detail.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: const TextStyle(
                    color: ArlColors.muted,
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SecurityRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final Widget trailing;
  final VoidCallback? onTap;

  const _SecurityRow({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final inner = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconBg,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: ArlColors.charcoal,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: ArlColors.muted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
    if (onTap == null) return inner;
    return InkWell(onTap: onTap, child: inner);
  }
}
