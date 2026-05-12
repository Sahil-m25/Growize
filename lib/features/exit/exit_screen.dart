import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:arl_app/core/navigation/route_names.dart';
import 'package:arl_app/core/supabase/supabase_client.dart';
import 'package:arl_app/core/theme/arl_colors.dart';

/// Fetches the earliest investment_date across all investor_units for the
/// current user. Returns null if no allocations exist yet.
///
/// Filters via RLS (`investor_id = auth.uid()`) instead of an explicit
/// `.eq('investor_id', uid)` so the query doesn't race with the session
/// restore on app launch.
final _earliestInvestmentDateProvider = FutureProvider<DateTime?>((ref) async {
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
      .select('investment_date')
      .not('investment_date', 'is', null)
      .order('investment_date', ascending: true)
      .limit(1)
      .maybeSingle();
  if (row == null || row['investment_date'] == null) return null;
  return DateTime.parse(row['investment_date'].toString());
});

class ExitScreen extends ConsumerWidget {
  const ExitScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final investmentDateAsync = ref.watch(_earliestInvestmentDateProvider);

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
          child: investmentDateAsync.when(
            data: (investmentDate) => _buildContent(context, investmentDate),
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.only(top: 40),
                child: CircularProgressIndicator(color: ArlColors.primary),
              ),
            ),
            error: (_, __) =>
                _buildContent(context, null), // fallback to no-data state
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, DateTime? investmentDate) {
    final dateFmt = DateFormat('MMM d, y');
    final now = DateTime.now();

    // Lock-in: investment_date + 5 years
    final lockInEnd = investmentDate != null
        ? DateTime(
            investmentDate.year + 5, investmentDate.month, investmentDate.day)
        : null;

    final isEligible = lockInEnd != null && now.isAfter(lockInEnd);

    // Time remaining
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
        // Exit Eligibility card
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
                      ? ArlColors.accent.withValues(alpha: 0.1)
                      : ArlColors.gold.withValues(alpha: 0.1),
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

        // Request Exit button
        SizedBox(
          width: double.infinity,
          child: isEligible
              ? ElevatedButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                            'Exit request submitted. Our team will review within 5 business days.'),
                        backgroundColor: ArlColors.primary,
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ArlColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  child: const Text(
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

        // Process flow info link
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
