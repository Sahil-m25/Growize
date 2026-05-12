import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:arl_app/core/theme/arl_colors.dart';
import 'package:arl_app/core/navigation/route_names.dart';
import 'package:arl_app/core/utils/money.dart';
import 'package:arl_app/features/home/models/portfolio_summary.dart';

class QuickStatsRow extends StatelessWidget {
  final PortfolioSummary portfolio;

  const QuickStatsRow({
    required this.portfolio,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final dateFormatter = DateFormat('MMM dd, yyyy');
    final hasPayout = portfolio.nextPayoutAmount > 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Next Payout Card — only when there's pending payout data
          if (hasPayout) ...[
            Expanded(
              child: GestureDetector(
                onTap: () => context.go(RouteNames.financials),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                      color: ArlColors.sand,
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.account_balance_wallet,
                            color: ArlColors.gold,
                            size: 18,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Next Payout',
                            style: TextStyle(
                              color: ArlColors.muted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        Money.inr(portfolio.nextPayoutAmount),
                        style: const TextStyle(
                          color: ArlColors.charcoal,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${dateFormatter.format(portfolio.nextPayoutDate)}'
                        '${portfolio.nextPayoutProjectName != null && portfolio.nextPayoutProjectName!.isNotEmpty ? ' · ${portfolio.nextPayoutProjectName}' : ''}',
                        style: const TextStyle(
                          color: ArlColors.accent,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],

          // Active Units Card
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: ArlColors.sand,
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.layers,
                        color: ArlColors.accent,
                        size: 18,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Active Units',
                        style: TextStyle(
                          color: ArlColors.muted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${portfolio.activeUnits} Units',
                    style: const TextStyle(
                      color: ArlColors.charcoal,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
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
          ),
        ],
      ),
    );
  }
}
