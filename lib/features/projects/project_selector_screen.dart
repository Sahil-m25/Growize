import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:arl_app/core/navigation/route_names.dart';
import 'package:arl_app/core/theme/arl_colors.dart';
import 'package:arl_app/core/utils/money.dart';
import 'package:arl_app/core/widgets/demo_badge.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arl_app/features/home/home_provider.dart';
import 'package:arl_app/features/projects/projects_provider.dart';

class ProjectSelectorScreen extends ConsumerWidget {
  const ProjectSelectorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedId = ref.watch(selectedProjectIdProvider);
    final projects = ref.watch(projectsProvider).valueOrNull ?? const [];
    final portfolio = ref.watch(portfolioSummaryProvider).valueOrNull;

    // Investor's actual aggregate (from portfolio_summary view), not
    // project capacity. Falls back to summing project ticket sizes only
    // when portfolio summary hasn't loaded yet.
    final investorTotalInvested = portfolio?.totalInvested ??
        projects.fold<double>(0, (sum, p) => sum + p.investedAmount);
    final investorTotalUnits = portfolio?.activeUnits ??
        projects.fold<int>(0, (sum, p) => sum + p.totalUnits);

    return Scaffold(
      backgroundColor: ArlColors.cream,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () {
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.go(RouteNames.home);
                      }
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Select Project',
                    style: TextStyle(
                      color: ArlColors.charcoal,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Filter your dashboard by project or view all consolidated.',
                    style: TextStyle(
                      color: ArlColors.muted,
                      fontSize: 12,
                    ),
                  ),
                  SizedBox(height: 16),
                ],
              ),
            ),

            // Cards list
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      // All Projects card — investor's own aggregate.
                      _projectCard(
                        context,
                        title: 'All Projects',
                        subtitle:
                            '${projects.length} ${projects.length == 1 ? 'Project' : 'Projects'} · '
                            '$investorTotalUnits ${investorTotalUnits == 1 ? 'Unit' : 'Units'} · '
                            '${Money.inr(investorTotalInvested, inline: true)} total',
                        icon: Icons.grid_view,
                        iconColor: ArlColors.gold,
                        isSelected: selectedId == null,
                        onTap: () {
                          ref.read(selectedProjectIdProvider.notifier).state =
                              null;
                          context.pop();
                        },
                      ),

                      // Individual project cards — investor-facing.
                      // Each card shows the investor's % share of their
                      // own portfolio, computed by amount (capital +
                      // token), not unit count, so projects with mixed
                      // tier sizes weight correctly.
                      ...projects.asMap().entries.map((entry) {
                        final project = entry.value;
                        final gradientColor = _parseColor(project.colorHex);

                        return Consumer(
                          builder: (context, ref2, _) {
                            final iu = ref2
                                .watch(investorAllocationProvider(project.id))
                                .valueOrNull;
                            final share =
                                (iu == null || investorTotalInvested <= 0)
                                    ? null
                                    : ((iu.capitalInvested +
                                                iu.tokenAdvanceAmount) /
                                            investorTotalInvested) *
                                        100;
                            final extra = share == null
                                ? null
                                : '${share.toStringAsFixed(share.truncateToDouble() == share ? 0 : 1)}% of portfolio';

                            return _projectCard(
                              context,
                              title: project.name,
                              subtitle: project.location,
                              status: project.status
                                      .toLowerCase()
                                      .contains('pending')
                                  ? 'Pending'
                                  : 'Active',
                              statusColor: project.status
                                      .toLowerCase()
                                      .contains('pending')
                                  ? ArlColors.earth
                                  : ArlColors.accent,
                              extraInfo: extra,
                              initials: project.initials,
                              initialsColor: gradientColor,
                              isSelected: selectedId == project.id,
                              isDemo: project.isDemo,
                              onTap: () {
                                ref
                                    .read(selectedProjectIdProvider.notifier)
                                    .state = project.id;
                                context.pop();
                              },
                            );
                          },
                        );
                      }),

                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _projectCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    String? status,
    Color? statusColor,
    String? extraInfo,
    IconData? icon,
    Color? iconColor,
    String? initials,
    Color? initialsColor,
    bool isSelected = false,
    bool isDemo = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: isSelected ? ArlColors.primary : ArlColors.sand,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Icon or initials
            if (icon != null)
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: ArlColors.sand,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Icon(
                    icon,
                    color: iconColor,
                    size: 20,
                  ),
                ),
              )
            else if (initials != null)
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      initialsColor!,
                      initialsColor.withValues(alpha: 0.7),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    initials,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            const SizedBox(width: 12),

            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                title,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: ArlColors.charcoal,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            DemoBadge(show: isDemo),
                          ],
                        ),
                      ),
                      if (status != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor!.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            status,
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: ArlColors.muted,
                      fontSize: 11,
                    ),
                  ),
                  if (extraInfo != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      extraInfo,
                      style: const TextStyle(
                        color: ArlColors.primary,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Check icon for selected
            if (isSelected)
              const Icon(
                Icons.check_circle,
                color: ArlColors.primary,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }

  Color _parseColor(String hexColor) {
    hexColor = hexColor.replaceAll('#', '');
    return Color(int.parse('FF$hexColor', radix: 16));
  }
}
