import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:arl_app/core/navigation/route_names.dart';
import 'package:arl_app/core/theme/arl_colors.dart';
import 'package:arl_app/core/utils/money.dart';
import 'package:arl_app/core/widgets/demo_badge.dart';
import 'package:arl_app/core/widgets/skel_box.dart';
import 'financials_provider.dart';
import 'package:arl_app/features/onboarding/tour_keys.dart';
import 'package:arl_app/features/projects/projects_provider.dart';

class FinancialsScreen extends ConsumerWidget {
  const FinancialsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payoutsData = ref.watch(payoutsProvider);
    final selectedProject = ref.watch(selectedProjectProvider);
    final portfolioData = ref.watch(scopedPortfolioProvider);

    return Scaffold(
      backgroundColor: ArlColors.cream,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Financials',
                    key: TourKeys.financialsHeader,
                    style: const TextStyle(
                      color: ArlColors.charcoal,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => context.push(RouteNames.projectSelector),
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: ArlColors.sand,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.location_on_outlined,
                            color: ArlColors.primary,
                            size: 14,
                          ),
                          const SizedBox(width: 6),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 120),
                            child: Text(
                              selectedProject?.name ?? 'All Projects',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: ArlColors.primary,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.keyboard_arrow_down,
                            color: ArlColors.primary,
                            size: 16,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Payouts content
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Tax-free banner
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: ArlColors.accent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: ArlColors.accent.withValues(alpha: 0.3),
                          ),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.verified_user,
                              color: ArlColors.accent,
                              size: 18,
                            ),
                            SizedBox(width: 10),
                            Text(
                              'Tax-Free under Sec 10(2A)',
                              style: TextStyle(
                                color: ArlColors.primary,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 2-col summary cards
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: portfolioData.when(
                        data: (p) {
                          final now = DateTime.now();
                          final fyStart = now.month >= 4
                              ? DateTime(now.year, 4, 1)
                              : DateTime(now.year - 1, 4, 1);
                          final allPayouts = payoutsData.valueOrNull ?? [];
                          final thisFy = allPayouts
                              .where((px) =>
                                  px.status == 'processed' &&
                                  px.date.isAfter(fyStart))
                              .fold<double>(
                                  0, (sum, px) => sum + px.amount);
                          return Row(
                            children: [
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        ArlColors.primary,
                                        ArlColors.accent,
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'TOTAL EARNED',
                                        style: TextStyle(
                                          color: Colors.white
                                              .withValues(alpha: 0.7),
                                          fontSize: 10,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        Money.inr(p.totalReceived),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      const Text(
                                        'Since inception',
                                        style: TextStyle(
                                          color: ArlColors.goldLight,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: ArlColors.gold
                                        .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: ArlColors.gold
                                          .withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'THIS FY',
                                        style: TextStyle(
                                          color: ArlColors.charcoal
                                              .withValues(alpha: 0.6),
                                          fontSize: 10,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        Money.inr(thisFy),
                                        style: const TextStyle(
                                          color: ArlColors.charcoal,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'FY ${fyStart.year}–${(fyStart.year + 1) % 100}',
                                        style: const TextStyle(
                                          color: ArlColors.primary,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                        loading: () => const Center(
                            child: CircularProgressIndicator()),
                        error: (_, __) => const SkelBox(height: 80),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Transaction Ledger
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Transaction Ledger',
                            style: TextStyle(
                              color: ArlColors.charcoal,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          payoutsData.when(
                            data: (payouts) => Column(
                              children: payouts.map((payout) {
                                final palette = <Color>[
                                  ArlColors.accent,
                                  const Color(0xFFA0522D),
                                  ArlColors.gold,
                                  ArlColors.primary,
                                  const Color(0xFF2D4A5E),
                                ];
                                final projectColor = palette[
                                    payout.projectId.hashCode.abs() %
                                        palette.length];
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: ArlColors.sand,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 4,
                                        height: 60,
                                        decoration: BoxDecoration(
                                          color: projectColor,
                                          borderRadius:
                                              BorderRadius.circular(2),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Text(
                                                  Money.inr(payout.amount),
                                                  style: const TextStyle(
                                                    color: ArlColors.charcoal,
                                                    fontSize: 12,
                                                    fontWeight:
                                                        FontWeight.bold,
                                                  ),
                                                ),
                                                DemoBadge(
                                                    show: payout.isDemo),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              payout.utrRef != null
                                                  ? '${payout.projectName} · Bank Transfer · UTR: ${payout.utrRef}'
                                                  : '${payout.projectName} · Awaiting transfer',
                                              style: const TextStyle(
                                                color: ArlColors.muted,
                                                fontSize: 10,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            payout.status == 'processed'
                                                ? 'Credited'
                                                : payout.status == 'pending'
                                                    ? 'Scheduled'
                                                    : payout.status,
                                            style: TextStyle(
                                              color: payout.status ==
                                                      'processed'
                                                  ? ArlColors.accent
                                                  : ArlColors.earth,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            DateFormat('MMM dd')
                                                .format(payout.date),
                                            style: const TextStyle(
                                              color: ArlColors.muted,
                                              fontSize: 10,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                            loading: () => Column(
                              children: List.generate(
                                  3,
                                  (_) => const SkelBox(
                                      height: 60,
                                      margin: EdgeInsets.only(bottom: 8))),
                            ),
                            error: (_, __) => Column(
                              children: List.generate(
                                  3,
                                  (_) => const SkelBox(
                                      height: 60,
                                      margin: EdgeInsets.only(bottom: 8))),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
