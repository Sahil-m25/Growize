import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:arl_app/core/navigation/route_names.dart';
import 'package:arl_app/core/providers/repositories.dart';
import 'package:arl_app/core/supabase/supabase_client.dart';
import 'package:arl_app/core/theme/arl_colors.dart';
import 'package:arl_app/features/auth/auth_provider.dart';

/// Earliest investor_units row for the current user — surface id +
/// investment_date together so the exit-request submit can FK to a
/// specific allocation. Filters via RLS rather than `.eq` to dodge
/// session-restore races.
final _earliestInvestorUnitProvider =
    FutureProvider<Map<String, dynamic>?>((ref) async {
  ref.watch(authStateProvider);
  final client = ArlSupabase.client;
  if (client == null) return null;

  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (
      client.auth.currentSession == null && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  if (client.auth.currentSession == null) return null;

  final row = await client
      .from('investor_units')
      .select('id, investment_date')
      .not('investment_date', 'is', null)
      .order('investment_date', ascending: true)
      .limit(1)
      .maybeSingle();
  if (row == null) return null;
  return Map<String, dynamic>.from(row);
});

/// Pending exit request for the earliest unit, if any. Drives the
/// "already submitted" UI state.
final _pendingExitForEarliestUnitProvider =
    FutureProvider<Map<String, dynamic>?>((ref) async {
  final unit = await ref.watch(_earliestInvestorUnitProvider.future);
  if (unit == null) return null;
  final id = unit['id'] as String?;
  if (id == null) return null;
  try {
    return await ref.read(exitRequestsRepositoryProvider).myPendingForUnit(id);
  } catch (_) {
    return null;
  }
});

class ExitScreen extends ConsumerStatefulWidget {
  const ExitScreen({super.key});

  @override
  ConsumerState<ExitScreen> createState() => _ExitScreenState();
}

class _ExitScreenState extends ConsumerState<ExitScreen> {
  bool _submitting = false;

  @override
  Widget build(BuildContext context) {
    final unitAsync = ref.watch(_earliestInvestorUnitProvider);
    final pendingAsync = ref.watch(_pendingExitForEarliestUnitProvider);

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
          'Project Exit',
          style: TextStyle(
            color: ArlColors.charcoal,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: unitAsync.when(
            data: (unit) => _buildContent(context, unit, pendingAsync),
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.only(top: 40),
                child: CircularProgressIndicator(color: ArlColors.primary),
              ),
            ),
            error: (_, __) => _buildContent(context, null, pendingAsync),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    Map<String, dynamic>? unit,
    AsyncValue<Map<String, dynamic>?> pendingAsync,
  ) {
    final dateFmt = DateFormat('MMM d, y');
    final now = DateTime.now();

    final unitId = unit?['id'] as String?;
    final investmentDate = unit?['investment_date'] == null
        ? null
        : DateTime.tryParse(unit!['investment_date'].toString());

    final lockInEnd = investmentDate != null
        ? DateTime(
            investmentDate.year + 5, investmentDate.month, investmentDate.day)
        : null;

    final isEligible = lockInEnd != null && now.isAfter(lockInEnd);
    final pending = pendingAsync.value;
    final hasPending = pending != null;

    String timeRemaining = '—';
    if (lockInEnd != null && !isEligible) {
      final diff = lockInEnd.difference(now);
      final years = diff.inDays ~/ 365;
      final months = (diff.inDays % 365) ~/ 30;
      final parts = <String>[];
      if (years > 0) parts.add('$years yr${years > 1 ? 's' : ''}');
      if (months > 0) parts.add('$months mo${months > 1 ? 's' : ''}');
      timeRemaining = parts.isEmpty ? 'Less than a month' : parts.join(' ');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: ArlColors.sand),
            boxShadow: const [
              BoxShadow(
                color: Color(0x143C5152),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Exit Eligibility',
                style: TextStyle(
                  color: ArlColors.charcoal,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              _eligibilityRow(
                'Investment Date',
                investmentDate != null ? dateFmt.format(investmentDate) : '—',
              ),
              const SizedBox(height: 8),
              _eligibilityRow(
                'Lock-in Ends',
                lockInEnd != null ? dateFmt.format(lockInEnd) : '—',
              ),
              const SizedBox(height: 12),
              const Divider(color: ArlColors.sand),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isEligible
                      ? ArlColors.accent.withOpacity(0.1)
                      : ArlColors.gold.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Row(
                  children: [
                    Icon(
                      isEligible
                          ? Icons.check_circle_outline
                          : Icons.lock_outline,
                      color: isEligible ? ArlColors.accent : ArlColors.earth,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isEligible
                          ? 'Eligible for exit'
                          : investmentDate != null
                              ? '$timeRemaining until eligible'
                              : 'No investment data available',
                      style: TextStyle(
                        color: isEligible ? ArlColors.accent : ArlColors.earth,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (hasPending)
          _SubmittedCard(submittedAt: pending['created_at'] as String?)
        else
          SizedBox(
            width: double.infinity,
            child: isEligible
                ? ElevatedButton(
                    onPressed: (_submitting || unitId == null)
                        ? null
                        : () => _onRequestExit(unitId),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ArlColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Request Exit',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  )
                : Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: ArlColors.sand,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.lock_outline,
                            color: ArlColors.muted, size: 16),
                        SizedBox(width: 8),
                        Text(
                          'Request Exit',
                          style: TextStyle(
                            color: ArlColors.muted,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    'Exit: Request → Review → Valuation → Settlement → Credit'),
                backgroundColor: ArlColors.charcoal,
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
          child: const Center(
            child: Text(
              'Learn about the exit process →',
              style: TextStyle(
                color: ArlColors.primary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _onRequestExit(String unitId) async {
    final reason = await _promptReason();
    if (reason == null) return;
    if (!mounted) return;

    setState(() => _submitting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await ref
          .read(exitRequestsRepositoryProvider)
          .createExit(investorUnitId: unitId, reason: reason);
      ref.invalidate(_pendingExitForEarliestUnitProvider);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(result.created
              ? 'Exit request submitted. Our team will review within 5 business days.'
              : 'You already have a pending exit request for this investment.'),
          backgroundColor: ArlColors.primary,
        ),
      );
    } catch (e, stack) {
      await Sentry.captureException(e,
          stackTrace: stack,
          withScope: (s) => s.setTag('flow', 'exit_request_submit'));
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Could not submit exit request: $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Modal asking why the investor is exiting. Returns trimmed reason
  /// (may be empty) or null on cancel.
  Future<String?> _promptReason() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text(
          'Reason for exit',
          style: TextStyle(
            color: ArlColors.charcoal,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          maxLength: 500,
          decoration: const InputDecoration(
            hintText: 'Optional — helps our team understand your needs',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  Widget _eligibilityRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(color: ArlColors.muted, fontSize: 12)),
        Text(value,
            style: const TextStyle(
                color: ArlColors.charcoal,
                fontSize: 12,
                fontWeight: FontWeight.w500)),
      ],
    );
  }
}

class _SubmittedCard extends StatelessWidget {
  final String? submittedAt;
  const _SubmittedCard({required this.submittedAt});

  @override
  Widget build(BuildContext context) {
    final parsed =
        submittedAt == null ? null : DateTime.tryParse(submittedAt!)?.toLocal();
    final whenText = parsed == null
        ? 'submitted'
        : 'submitted on ${DateFormat('MMM d, y').format(parsed)}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ArlColors.accent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: ArlColors.accent.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle_outline,
              color: ArlColors.accent, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Exit request pending review',
                  style: TextStyle(
                    color: ArlColors.charcoal,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Your request was $whenText. ARL ops will reach out within '
                  '5 business days with valuation and settlement steps.',
                  style: const TextStyle(
                    color: ArlColors.charcoal,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
