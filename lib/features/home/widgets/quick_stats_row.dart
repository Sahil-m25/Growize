import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:arl_app/core/theme/arl_colors.dart';
import 'package:arl_app/core/navigation/route_names.dart';
import 'package:arl_app/core/utils/money.dart';
import 'package:arl_app/features/home/models/portfolio_summary.dart';

/// Quick Stats row under the Portfolio hero card.
///
/// Mirrors HTML `quick-stats-grid` — a two-column grid with **Active
/// Units** on the left and **Next Payout** on the right. Both cards
/// always render so the layout doesn't reflow when payout data lands;
/// when no payout is scheduled the right card shows a friendly
/// placeholder instead of being hidden.
///
/// Taps:
///   * Active Units → Projects tab
///   * Next Payout  → Financials (default sub-tab = Payouts)
class QuickStatsRow extends StatelessWidget {
  final PortfolioSummary portfolio;

  const QuickStatsRow({
    required this.portfolio,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final hasPayout = portfolio.nextPayoutAmount > 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Active Units (left) ─────────────────────────────────
            Expanded(
              child: _ActiveUnitsCard(portfolio: portfolio),
            ),
            const SizedBox(width: 12),
            // ── Next Payout (right) ─────────────────────────────────
            Expanded(
              child: _NextPayoutCard(
                portfolio: portfolio,
                hasPayout: hasPayout,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// White card · rounded-15 · border `ArlColors.sand` (#E1DFC6 ≈ #D4D2B4
/// in the HTML) · accent/15 icon disc + layers icon + "Active Units"
/// small muted label · bold "<n> Units" · muted sub-line with project
/// count. Tap navigates to the Projects tab.
class _ActiveUnitsCard extends StatelessWidget {
  final PortfolioSummary portfolio;
  const _ActiveUnitsCard({required this.portfolio});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.go(RouteNames.projects),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: _cardDeco(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _IconDisc(
                  icon: Icons.layers_outlined,
                  tint: ArlColors.accent,
                ),
                const SizedBox(width: 8),
                const Flexible(
                  child: Text(
                    'Active Units',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: ArlColors.muted,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              portfolio.activeUnits == 1
                  ? '1 Unit'
                  : '${portfolio.activeUnits} Units',
              style: const TextStyle(
                color: ArlColors.charcoal,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              portfolio.projectCount == 1
                  ? '1 Project'
                  : '${portfolio.projectCount} Projects',
              style: const TextStyle(
                color: ArlColors.muted,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// White card · rounded-15 · border `ArlColors.sand` · gold/15 icon disc
/// + wallet icon + "Next Payout" muted label · bold ₹ amount · muted
/// "<date> · <project>" (project shown in accent). Tap navigates to
/// Financials with Payouts as the (default) active sub-tab.
///
/// When no payout is scheduled, the card still renders so the row
/// doesn't collapse — body shows a calm "No payout scheduled" state.
class _NextPayoutCard extends StatelessWidget {
  final PortfolioSummary portfolio;
  final bool hasPayout;
  const _NextPayoutCard({required this.portfolio, required this.hasPayout});

  @override
  Widget build(BuildContext context) {
    final dateFormatter = DateFormat('MMM dd, yyyy');

    return GestureDetector(
      onTap: () => context.go(RouteNames.financials),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: _cardDeco(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _IconDisc(
                  icon: Icons.account_balance_wallet_outlined,
                  tint: ArlColors.gold,
                ),
                const SizedBox(width: 8),
                const Flexible(
                  child: Text(
                    'Next Payout',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: ArlColors.muted,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              hasPayout ? Money.inr(portfolio.nextPayoutAmount) : '—',
              style: const TextStyle(
                color: ArlColors.charcoal,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            if (hasPayout)
              _PayoutSubLine(
                date: dateFormatter.format(portfolio.nextPayoutDate),
                projectName: portfolio.nextPayoutProjectName,
              )
            else
              const Text(
                'No payout scheduled',
                style: TextStyle(
                  color: ArlColors.muted,
                  fontSize: 10,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// "Apr 15, 2026 · <ProjectName>" with the project name styled in accent
/// per HTML. The date itself stays muted so the project pops as the link
/// affordance.
class _PayoutSubLine extends StatelessWidget {
  final String date;
  final String? projectName;
  const _PayoutSubLine({required this.date, required this.projectName});

  @override
  Widget build(BuildContext context) {
    final hasProject = projectName != null && projectName!.isNotEmpty;
    return RichText(
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: const TextStyle(
          color: ArlColors.muted,
          fontSize: 10,
        ),
        children: [
          TextSpan(text: date),
          if (hasProject) ...[
            const TextSpan(text: ' · '),
            TextSpan(
              text: projectName,
              style: const TextStyle(
                color: ArlColors.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Small tinted disc behind the card's lead icon. Mirrors HTML's
/// `bg-arl-{tint}/15` icon-circle pattern.
class _IconDisc extends StatelessWidget {
  final IconData icon;
  final Color tint;
  const _IconDisc({required this.icon, required this.tint});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: tint.withOpacity(0.15),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: tint, size: 16),
    );
  }
}

BoxDecoration _cardDeco() => BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(15),
      border: Border.all(color: ArlColors.sand, width: 1),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.06),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    );
