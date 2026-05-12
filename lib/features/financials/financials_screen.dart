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
import 'package:arl_app/features/projects/projects_provider.dart';

class FinancialsScreen extends ConsumerStatefulWidget {
  const FinancialsScreen({super.key});

  @override
  ConsumerState<FinancialsScreen> createState() => _FinancialsScreenState();
}

class _FinancialsScreenState extends ConsumerState<FinancialsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                  const Text(
                    'Financials',
                    style: TextStyle(
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

            // Tab bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _tabPill(
                    'Payouts',
                    _tabController.index == 0,
                    onTap: () {
                      _tabController.animateTo(0);
                    },
                  ),
                  const SizedBox(width: 8),
                  _tabPill(
                    'Financials',
                    _tabController.index == 1,
                    onTap: () {
                      _tabController.animateTo(1);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Tab content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  // Payouts Tab
                  SingleChildScrollView(
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

                        // 2-col cards — This FY calculated from payouts
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: portfolioData.when(
                            data: (p) {
                              // Compute This FY earnings from payouts list.
                              final now = DateTime.now();
                              // Indian FY starts April 1.
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
                                    // Stable colour per project — hash the id
                                    // so the same project always gets the
                                    // same accent stripe across rows.
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
                                                        color:
                                                            ArlColors.charcoal,
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

                  // Financials Tab
                  SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 12),
                          // Risk vs Return Card
                          _riskReturnCard(context),
                          const SizedBox(height: 16),

                          // 2-col grid — driven by portfolio_summary view
                          portfolioData.when(
                            data: (p) => Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: ArlColors.sand,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Invested',
                                          style: TextStyle(
                                            color: ArlColors.muted,
                                            fontSize: 10,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          _formatInr(p.totalInvested),
                                          style: const TextStyle(
                                            color: ArlColors.charcoal,
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
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
                                      color: ArlColors.accent
                                          .withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: ArlColors.accent
                                            .withValues(alpha: 0.3),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Returns',
                                          style: TextStyle(
                                            color: ArlColors.muted,
                                            fontSize: 10,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          _formatInr(p.totalReceived),
                                          style: const TextStyle(
                                            color: ArlColors.accent,
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            loading: () => const SkelBox(height: 64),
                            error: (_, __) => const SkelBox(height: 64),
                          ),
                          const SizedBox(height: 16),

                          // Capital Account
                          portfolioData.when(
                            data: (p) => Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: ArlColors.sand,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Capital Account',
                                    style: TextStyle(
                                      color: ArlColors.charcoal,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  _capitalRow(
                                      'Committed',
                                      Money.inr(p.totalInvested),
                                      ArlColors.sand),
                                  _capitalRow(
                                      'Received',
                                      Money.inr(p.totalReceived),
                                      ArlColors.accent.withValues(alpha: 0.1),
                                      checkIcon: true),
                                  _capitalRow(
                                      'Pending',
                                      Money.inr(p.pendingAmount),
                                      ArlColors.earth.withValues(alpha: 0.1)),
                                ],
                              ),
                            ),
                            loading: () => const SkelBox(height: 120),
                            error: (_, __) => const SkelBox(height: 120),
                          ),
                          const SizedBox(height: 16),

                          // Earnings Outlook
                          portfolioData.when(
                            data: (p) {
                              final avgYield = p.avgAnnualYieldPct > 0
                                  ? p.avgAnnualYieldPct
                                  : 0.0;
                              // 5-year compound projection using avg yield.
                              // Each Y(n) = invested * (1 + yield/100)^n
                              final rate = avgYield / 100;
                              double cpow(double b, int e) {
                                double r = 1.0;
                                for (int i = 0; i < e; i++) {
                                  r *= b;
                                }
                                return r;
                              }

                              final years = List.generate(5, (i) {
                                final n = i + 1;
                                final projected = p.totalInvested > 0
                                    ? p.totalInvested * cpow(1 + rate, n)
                                    : 0.0;
                                final yieldPct = avgYield > 0
                                    ? ((cpow(1 + rate, n) - 1) * 100)
                                    : 0.0;
                                return ('Y$n', yieldPct, projected);
                              });
                              return Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: ArlColors.sand),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Earnings Outlook',
                                      style: TextStyle(
                                        color: ArlColors.charcoal,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    const Text(
                                      'Avg Annual Yield (your portfolio)',
                                      style: TextStyle(
                                        color: ArlColors.muted,
                                        fontSize: 11,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      avgYield > 0
                                          ? '${avgYield.toStringAsFixed(avgYield.truncateToDouble() == avgYield ? 0 : 1)}%'
                                          : '—',
                                      style: const TextStyle(
                                        color: ArlColors.charcoal,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceAround,
                                      children: years.map((y) {
                                        final label = y.$1;
                                        final yieldPct = y.$2;
                                        // Bar height fraction: Y5 is full, scale rest proportionally.
                                        final maxPct = years.last.$2;
                                        final h = maxPct > 0
                                            ? 0.3 + (yieldPct / maxPct) * 0.7
                                            : 0.05;
                                        return _barChart(
                                          label,
                                          h.clamp(0.0, 1.0),
                                          avgYield > 0
                                              ? '${yieldPct.toStringAsFixed(0)}%'
                                              : '—',
                                        );
                                      }).toList(),
                                    ),
                                  ],
                                ),
                              );
                            },
                            loading: () => const SkelBox(height: 100),
                            error: (_, __) => const SkelBox(height: 100),
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Bridge to the shared Money helper. Kept as a private method so
  /// the widget tree below stays unchanged.
  String _formatInr(num value) => Money.inr(value, inline: true);

  Widget _tabPill(String label, bool isActive, {required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? ArlColors.primary : ArlColors.sand,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.white : ArlColors.primary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _riskReturnCard(BuildContext context) {
    // Local helper: dot Positioned widget
    Widget makeDot(
        double w, double h, double rx, double ry, Color color, bool isStar) {
      final x = rx * w;
      final y = (1 - ry) * h;
      final size = isStar ? 12.0 : 8.0;
      return Positioned(
        left: x - size / 2,
        top: y - size / 2,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: isStar ? Border.all(color: ArlColors.gold, width: 2) : null,
            boxShadow: isStar
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.5),
                      blurRadius: 8,
                      spreadRadius: 1,
                    )
                  ]
                : null,
          ),
        ),
      );
    }

    // Local helper: label Positioned widget
    Widget makeLabel(
        double w, double h, double rx, double ry, String text, bool isStar) {
      final x = rx * w;
      final y = (1 - ry) * h;
      return Positioned(
        left: x + (isStar ? 8 : 6),
        top: y - 9,
        child: Text(
          text,
          style: TextStyle(
            fontSize: 7,
            height: 1.3,
            fontWeight: isStar ? FontWeight.w700 : FontWeight.w400,
            color: isStar ? ArlColors.primary : ArlColors.muted,
          ),
        ),
      );
    }

    const assetRx = [0.13, 0.24, 0.38, 0.30, 0.74, 0.19];
    const assetRy = [0.27, 0.50, 0.63, 0.37, 0.60, 0.88];
    final assetColors = [
      Colors.grey.shade500,
      Colors.green.shade400,
      Colors.blue.shade400,
      const Color(0xFFD4AF37),
      Colors.deepOrange.shade400,
      ArlColors.primary,
    ];
    const assetLabels = [
      'Fixed\nDeposit',
      'Fixed\nIncome',
      'REITs',
      'Gold',
      'Direct\nEquity',
      'Growize\nEKA',
    ];
    const assetStar = [false, false, false, false, false, true];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ArlColors.sand),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Risk vs Return',
            style: TextStyle(
                color: ArlColors.charcoal,
                fontSize: 12,
                fontWeight: FontWeight.w600),
          ),
          const Text('India HNI · Asset Comparison',
              style: TextStyle(color: ArlColors.muted, fontSize: 10)),
          const SizedBox(height: 12),
          SizedBox(
            height: 220,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: RotatedBox(
                    quarterTurns: 3,
                    child: Text(
                      'Return  →',
                      style: TextStyle(
                          color: ArlColors.muted,
                          fontSize: 8,
                          letterSpacing: 0.5),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final w = constraints.maxWidth;
                            final h = constraints.maxHeight;
                            return Stack(
                              clipBehavior: Clip.hardEdge,
                              children: [
                                // Top-left: Low Risk / High Return — green (ideal)
                                Positioned(
                                  left: 0,
                                  top: 0,
                                  width: w / 2,
                                  height: h / 2,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: ArlColors.arlGreen
                                          .withValues(alpha: 0.09),
                                      border: const Border(
                                        right: BorderSide(
                                            color: ArlColors.sand, width: 0.5),
                                        bottom: BorderSide(
                                            color: ArlColors.sand, width: 0.5),
                                      ),
                                    ),
                                  ),
                                ),
                                // Top-right: High Risk / High Return — amber
                                Positioned(
                                  left: w / 2,
                                  top: 0,
                                  width: w / 2,
                                  height: h / 2,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.amber.withValues(alpha: 0.07),
                                      border: const Border(
                                        bottom: BorderSide(
                                            color: ArlColors.sand, width: 0.5),
                                      ),
                                    ),
                                  ),
                                ),
                                // Bottom-left: Low Risk / Low Return — gray
                                Positioned(
                                  left: 0,
                                  top: h / 2,
                                  width: w / 2,
                                  height: h / 2,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.grey.withValues(alpha: 0.05),
                                      border: const Border(
                                        right: BorderSide(
                                            color: ArlColors.sand, width: 0.5),
                                      ),
                                    ),
                                  ),
                                ),
                                // Bottom-right: High Risk / Low Return — red
                                Positioned(
                                  left: w / 2,
                                  top: h / 2,
                                  width: w / 2,
                                  height: h / 2,
                                  child: Container(
                                      color:
                                          Colors.red.withValues(alpha: 0.06)),
                                ),
                                // Quadrant corner labels
                                Positioned(
                                  left: 4,
                                  top: 4,
                                  child: Text('LOW RISK\nHIGH RETURN',
                                      style: TextStyle(
                                          color: ArlColors.arlGreen
                                              .withValues(alpha: 0.75),
                                          fontSize: 6.5,
                                          fontWeight: FontWeight.w600,
                                          height: 1.4)),
                                ),
                                Positioned(
                                  right: 4,
                                  top: 4,
                                  child: Text('HIGH RISK\nHIGH RETURN',
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                          color: Colors.amber.shade700
                                              .withValues(alpha: 0.75),
                                          fontSize: 6.5,
                                          height: 1.4)),
                                ),
                                Positioned(
                                  left: 4,
                                  bottom: 4,
                                  child: Text('LOW RISK\nLOW RETURN',
                                      style: TextStyle(
                                          color: Colors.grey
                                              .withValues(alpha: 0.6),
                                          fontSize: 6.5,
                                          height: 1.4)),
                                ),
                                Positioned(
                                  right: 4,
                                  bottom: 4,
                                  child: Text('HIGH RISK\nLOW RETURN',
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                          color:
                                              Colors.red.withValues(alpha: 0.6),
                                          fontSize: 6.5,
                                          height: 1.4)),
                                ),
                                // Asset dots
                                ...List.generate(
                                  6,
                                  (i) => makeDot(w, h, assetRx[i], assetRy[i],
                                      assetColors[i], assetStar[i]),
                                ),
                                // Asset labels
                                ...List.generate(
                                  6,
                                  (i) => makeLabel(w, h, assetRx[i], assetRy[i],
                                      assetLabels[i], assetStar[i]),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          'Risk  →',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: ArlColors.muted,
                              fontSize: 8,
                              letterSpacing: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Source: AMFI · SEBI Guidelines',
            style: TextStyle(
                color: ArlColors.muted, fontSize: 9, letterSpacing: 0.3),
          ),
        ],
      ),
    );
  }

  Widget _capitalRow(String label, String value, Color bgColor,
      {bool checkIcon = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              if (checkIcon)
                const Icon(
                  Icons.check_circle,
                  size: 14,
                  color: ArlColors.accent,
                )
              else
                const SizedBox(width: 14),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: ArlColors.muted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          Text(
            value,
            style: const TextStyle(
              color: ArlColors.charcoal,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _barChart(String label, double heightFraction, String pct) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          pct,
          style: const TextStyle(
            color: ArlColors.primary,
            fontSize: 8,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        Container(
          width: 22,
          height: 60 * heightFraction,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [ArlColors.primary, ArlColors.gold],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(color: ArlColors.muted, fontSize: 9),
        ),
      ],
    );
  }
}
