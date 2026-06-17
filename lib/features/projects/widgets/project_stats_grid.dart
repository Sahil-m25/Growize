import 'package:flutter/material.dart';

import '../../../core/theme/arl_colors.dart';
import '../../../core/utils/money.dart';
import '../models/investor_unit.dart';
import '../models/project.dart';

/// "Your Investment" stats grid — mirrors v3 R3 block in the HTML
/// per-project view (`projects-{gv|so|va}-view`).
///
/// 2×2 grid:
///   Units Owned · Total Invested
///   Expected Return · Payouts to Date
///
/// Below the grid a slim Contract Progress bar with start/end labels.
/// All formatting is INR Lakh/Crore aware via [Money.inr].
class ProjectStatsGrid extends StatelessWidget {
  final Project project;
  final InvestorUnit? investor;

  /// Sum of all *processed* non-demo payouts for this project, sourced from
  /// the payouts table. Pass 0.0 when there are no payouts yet. This replaces
  /// the previous (incorrect) use of investor_units.total_amount_received,
  /// which represents the investor's capital payment, not a distribution.
  final double payoutsTotal;

  const ProjectStatsGrid({
    super.key,
    required this.project,
    required this.investor,
    this.payoutsTotal = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    final iu = investor;

    final units = iu?.issuedUnits.toString() ?? '—';
    final invested = iu == null
        ? '—'
        : Money.inr(
            iu.capitalInvested + iu.tokenAdvanceAmount,
            inline: true,
          );
    final yieldPct = iu == null
        ? '—'
        : '${_fmtPct(iu.annualYieldPct)}%';
    final payouts = iu == null
        ? '—'
        : Money.inr(payoutsTotal, inline: true);

    final payoutsSince = iu?.investmentDate != null
        ? 'since ${_monthYear(iu!.investmentDate!)}'
        : null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: ArlColors.sand),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your Investment',
            style: TextStyle(
              color: ArlColors.charcoal,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 2.3,
            children: [
              _tile(
                label: 'Units Owned',
                value: units,
                valueColor: ArlColors.charcoal,
                background: ArlColors.sand.withOpacity(0.4),
                borderColor: ArlColors.sand,
              ),
              _tile(
                label: 'Total Invested',
                value: invested,
                valueColor: ArlColors.charcoal,
                background: ArlColors.sand.withOpacity(0.4),
                borderColor: ArlColors.sand,
              ),
              _tile(
                label: 'Expected Return',
                value: yieldPct,
                valueColor: ArlColors.accent,
                background: ArlColors.accent.withOpacity(0.1),
                borderColor: ArlColors.accent.withOpacity(0.3),
                subtitle: iu == null ? null : 'annual',
              ),
              _tile(
                label: 'Payouts to Date',
                value: payouts,
                valueColor: ArlColors.gold,
                background: ArlColors.gold.withOpacity(0.1),
                borderColor: ArlColors.gold.withOpacity(0.3),
                subtitle: payoutsSince,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tile({
    required String label,
    required String value,
    required Color valueColor,
    required Color background,
    required Color borderColor,
    String? subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: ArlColors.muted,
              fontSize: 9,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 1),
            Text(
              subtitle,
              style: const TextStyle(
                color: ArlColors.muted,
                fontSize: 9,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  static String _fmtPct(double pct) {
    final isWhole = pct.truncateToDouble() == pct;
    return isWhole ? pct.toStringAsFixed(0) : pct.toStringAsFixed(1);
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _monthYear(DateTime d) => '${_months[d.month - 1]} ${d.year}';
}
