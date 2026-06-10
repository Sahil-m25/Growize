import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:arl_app/core/navigation/route_names.dart';
import 'package:arl_app/core/repositories/privacy_repository.dart';
import 'package:arl_app/core/theme/arl_colors.dart';
import 'package:arl_app/features/legal/legal_content.dart';

/// Profile → Privacy & Data. Surfaces the DPDP data-principal rights:
///   • Access / export — download a copy of all data we hold.
///   • Nomination — name someone to act if you die or are incapacitated.
///   • Erasure — request deletion (ops honours statutory retention).
/// Consent + withdrawal live on the Security screen.
final _nomineeProvider =
    FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  return ref.read(privacyRepositoryProvider).getNominee();
});
final _erasureProvider =
    FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  return ref.read(privacyRepositoryProvider).latestErasureRequest();
});

class PrivacyScreen extends ConsumerStatefulWidget {
  const PrivacyScreen({super.key});

  @override
  ConsumerState<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends ConsumerState<PrivacyScreen> {
  bool _exporting = false;

  @override
  Widget build(BuildContext context) {
    final nomineeAsync = ref.watch(_nomineeProvider);
    final erasureAsync = ref.watch(_erasureProvider);

    return Scaffold(
      backgroundColor: ArlColors.cream,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: ArlColors.charcoal),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(RouteNames.home),
        ),
        title: const Text('Privacy & Data',
            style: TextStyle(
                color: ArlColors.charcoal,
                fontSize: 16,
                fontWeight: FontWeight.w600)),
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Exercise your rights under the Digital Personal Data '
              'Protection Act. For help, contact our Grievance Officer at '
              '${LegalDocs.contactEmail}.',
              style: TextStyle(
                  color: ArlColors.muted, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 16),

            // ── Access / export ─────────────────────────────────────
            _Card(
              icon: Icons.download_outlined,
              title: 'Download my data',
              subtitle:
                  'Get a copy of the personal data we hold about you (profile, '
                  'investments, payouts, documents, consents and more).',
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _exporting ? null : _export,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: ArlColors.primary,
                    side: const BorderSide(color: ArlColors.primary),
                  ),
                  child: _exporting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: ArlColors.primary))
                      : const Text('Prepare my data'),
                ),
              ),
            ),

            // ── Nomination ──────────────────────────────────────────
            _Card(
              icon: Icons.people_alt_outlined,
              title: 'Nominee',
              subtitle:
                  'Name someone who can exercise your rights over this data '
                  'if you pass away or become unable to.',
              child: nomineeAsync.when(
                loading: () => const _MiniLoader(),
                error: (_, __) => const Text('Could not load nominee.',
                    style: TextStyle(color: ArlColors.muted, fontSize: 12)),
                data: (n) => n == null
                    ? Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => _nomineeDialog(),
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Add nominee'),
                          style: TextButton.styleFrom(
                              foregroundColor: ArlColors.primary),
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(n['name'] as String? ?? '',
                              style: const TextStyle(
                                  color: ArlColors.charcoal,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600)),
                          if ((n['relationship'] as String?)?.isNotEmpty ??
                              false)
                            Text(n['relationship'] as String,
                                style: const TextStyle(
                                    color: ArlColors.muted, fontSize: 12)),
                          if ((n['email'] as String?)?.isNotEmpty ?? false)
                            Text(n['email'] as String,
                                style: const TextStyle(
                                    color: ArlColors.muted, fontSize: 12)),
                          if ((n['phone'] as String?)?.isNotEmpty ?? false)
                            Text(n['phone'] as String,
                                style: const TextStyle(
                                    color: ArlColors.muted, fontSize: 12)),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              TextButton(
                                onPressed: () => _nomineeDialog(existing: n),
                                style: TextButton.styleFrom(
                                    foregroundColor: ArlColors.primary),
                                child: const Text('Edit'),
                              ),
                              TextButton(
                                onPressed: _removeNominee,
                                style: TextButton.styleFrom(
                                    foregroundColor: ArlColors.earth),
                                child: const Text('Remove'),
                              ),
                            ],
                          ),
                        ],
                      ),
              ),
            ),

            // ── Erasure ─────────────────────────────────────────────
            _Card(
              icon: Icons.delete_outline,
              title: 'Erase my data',
              subtitle:
                  'Request deletion of your personal data. We will erase what '
                  'we can, but some KYC and financial records must be kept for '
                  'the period required by law (e.g. PMLA, Companies Act).',
              child: erasureAsync.when(
                loading: () => const _MiniLoader(),
                error: (_, __) => _erasureButton(),
                data: (req) {
                  final status = req?['status'] as String?;
                  if (status == 'pending' || status == 'in_progress') {
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: ArlColors.gold.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'Erasure request received (status: $status). Our team '
                        'will action it within the required timeline and '
                        'contact you at the email on file.',
                        style: const TextStyle(
                            color: ArlColors.charcoal, fontSize: 12),
                      ),
                    );
                  }
                  return _erasureButton();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _erasureButton() => Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton(
          onPressed: _confirmErasure,
          style: OutlinedButton.styleFrom(
            foregroundColor: ArlColors.earth,
            side: const BorderSide(color: ArlColors.earth),
          ),
          child: const Text('Request data erasure'),
        ),
      );

  Future<void> _export() async {
    setState(() => _exporting = true);
    final repo = ref.read(privacyRepositoryProvider);
    try {
      final data = await repo.exportMyData();
      final json = repo.toPrettyJson(data);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          title: const Text('Your data',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: SelectableText(json,
                  style: const TextStyle(fontSize: 11, height: 1.4)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: json));
                if (ctx.mounted) Navigator.of(ctx).pop();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Copied to clipboard.')));
                }
              },
              child: const Text('Copy'),
            ),
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Close')),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not export: $e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _nomineeDialog({Map<String, dynamic>? existing}) async {
    final name = TextEditingController(text: existing?['name'] as String? ?? '');
    final rel = TextEditingController(
        text: existing?['relationship'] as String? ?? '');
    final email =
        TextEditingController(text: existing?['email'] as String? ?? '');
    final phone =
        TextEditingController(text: existing?['phone'] as String? ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(existing == null ? 'Add nominee' : 'Edit nominee',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dlgField(name, 'Full name *'),
              _dlgField(rel, 'Relationship'),
              _dlgField(email, 'Email'),
              _dlgField(phone, 'Phone'),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              if (name.text.trim().isEmpty) return;
              Navigator.of(ctx).pop(true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved != true) return;
    try {
      await ref.read(privacyRepositoryProvider).upsertNominee(
            name: name.text.trim(),
            relationship: rel.text,
            email: email.text,
            phone: phone.text,
          );
      ref.invalidate(_nomineeProvider);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Nominee saved.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    }
  }

  Future<void> _removeNominee() async {
    try {
      await ref.read(privacyRepositoryProvider).deleteNominee();
      ref.invalidate(_nomineeProvider);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Nominee removed.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not remove: $e')));
      }
    }
  }

  Future<void> _confirmErasure() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Request data erasure',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        content: const Text(
          'We will erase the personal data we are not required to keep. KYC '
          'and financial records must be retained for the period required by '
          'law and cannot be deleted earlier. Our team will process your '
          'request and contact you. Continue?',
          style: TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: ArlColors.earth),
            child: const Text('Request erasure'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(privacyRepositoryProvider).requestErasure();
      ref.invalidate(_erasureProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Erasure request submitted.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not submit: $e')));
      }
    }
  }

  Widget _dlgField(TextEditingController c, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
        ),
      );
}

class _Card extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;
  const _Card({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: ArlColors.sand, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: ArlColors.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: ArlColors.primary, size: 17),
              ),
              const SizedBox(width: 10),
              Text(title,
                  style: const TextStyle(
                      color: ArlColors.charcoal,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 8),
          Text(subtitle,
              style: const TextStyle(
                  color: ArlColors.muted, fontSize: 12, height: 1.4)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _MiniLoader extends StatelessWidget {
  const _MiniLoader();
  @override
  Widget build(BuildContext context) => const SizedBox(
        height: 24,
        child: Center(
          child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: ArlColors.accent)),
        ),
      );
}
