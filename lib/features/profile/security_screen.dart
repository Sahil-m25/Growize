import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:arl_app/core/navigation/route_names.dart';
import 'package:arl_app/core/providers/repositories.dart';
import 'package:arl_app/core/theme/arl_colors.dart';

class SecurityScreen extends ConsumerWidget {
  const SecurityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(userSettingsProvider);
    final loginsAsync = ref.watch(myLoginEventsProvider);

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
          final biometricEnabled =
              (settings?['biometric_enabled'] as bool?) ?? false;
          final notificationsEnabled =
              (settings?['notifications_enabled'] as bool?) ?? true;
          final pinSet = settings?['app_pin_hash'] != null;
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
                        _SecurityRow(
                          icon: Icons.fingerprint,
                          iconColor: ArlColors.accent,
                          iconBg: ArlColors.accent.withValues(alpha: 0.15),
                          title: 'Biometric Login',
                          subtitle: biometricEnabled ? 'Enabled' : 'Disabled',
                          trailing: Switch(
                            value: biometricEnabled,
                            onChanged: (v) => _setBiometric(context, ref, v),
                            activeThumbColor: ArlColors.accent,
                            inactiveThumbColor: ArlColors.muted,
                          ),
                        ),
                        const Divider(
                            height: 1, color: ArlColors.sand, thickness: 1),
                        _SecurityRow(
                          icon: Icons.smartphone,
                          iconColor: ArlColors.primary,
                          iconBg: ArlColors.primary.withValues(alpha: 0.1),
                          title: 'App PIN',
                          subtitle: pinSet ? 'Set' : 'Not set',
                          onTap: () => _openPinFlow(context, ref, pinSet),
                          trailing: const Icon(Icons.chevron_right,
                              color: ArlColors.primary, size: 18),
                        ),
                        const Divider(
                            height: 1, color: ArlColors.sand, thickness: 1),
                        _SecurityRow(
                          icon: Icons.notifications_outlined,
                          iconColor: ArlColors.gold,
                          iconBg: ArlColors.gold.withValues(alpha: 0.15),
                          title: 'Notifications',
                          subtitle: notificationsEnabled ? 'On' : 'Off',
                          trailing: Switch(
                            value: notificationsEnabled,
                            onChanged: (v) =>
                                _setNotifications(context, ref, v),
                            activeThumbColor: ArlColors.gold,
                            inactiveThumbColor: ArlColors.muted,
                          ),
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
                          'Auto-lock after',
                          style: TextStyle(
                            color: ArlColors.charcoal,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Row(
                          children: [
                            Text(
                              '5 minutes',
                              style: TextStyle(
                                color: ArlColors.muted,
                                fontSize: 12,
                              ),
                            ),
                            SizedBox(width: 8),
                            Icon(
                              Icons.chevron_right,
                              color: ArlColors.primary,
                              size: 18,
                            ),
                          ],
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
    // Enabling biometric login requires the user to pass a real
    // biometric check first — gate via BiometricScreen which pops
    // with true/false. Disabling does not need a fresh check.
    if (value) {
      final ok = await context.push<bool>(RouteNames.biometric);
      if (ok != true) {
        // User cancelled or biometric failed — keep toggle off.
        ref.invalidate(userSettingsProvider);
        return;
      }
    }
    try {
      await ref
          .read(userSettingsRepositoryProvider)
          .updateToggles(biometricEnabled: value);
      ref.invalidate(userSettingsProvider);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not save: $e')),
      );
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

    switch (action) {
      case _PinAction.set:
        final pin = await _promptNewPin(context);
        if (pin == null) return;
        try {
          await repo.setPin(pin);
          ref.invalidate(userSettingsProvider);
          messenger.showSnackBar(const SnackBar(content: Text('PIN set.')));
        } catch (e) {
          messenger
              .showSnackBar(SnackBar(content: Text('Could not set PIN: $e')));
        }
        return;
      case _PinAction.change:
        final current = await _promptPin(context, title: 'Enter current PIN');
        if (current == null) return;
        if (!context.mounted) return;
        final next = await _promptNewPin(context);
        if (next == null) return;
        try {
          final ok = await repo.changePin(currentPin: current, newPin: next);
          ref.invalidate(userSettingsProvider);
          messenger.showSnackBar(SnackBar(
              content: Text(ok ? 'PIN updated.' : 'Current PIN incorrect.')));
        } catch (e) {
          messenger.showSnackBar(
              SnackBar(content: Text('Could not change PIN: $e')));
        }
        return;
      case _PinAction.remove:
        final current = await _promptPin(context, title: 'Enter current PIN');
        if (current == null) return;
        final ok = await repo.verifyPin(current);
        if (!ok) {
          messenger.showSnackBar(
              const SnackBar(content: Text('Current PIN incorrect.')));
          return;
        }
        await repo.clearPin();
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
            color: ArlColors.muted.withValues(alpha: 0.12),
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
