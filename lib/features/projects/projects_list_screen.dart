import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:arl_app/core/theme/arl_colors.dart';
import 'package:arl_app/core/utils/money.dart';
import 'package:arl_app/core/widgets/skel_box.dart';
import 'package:arl_app/features/home/home_provider.dart';
import 'package:arl_app/features/projects/models/investor_unit.dart';
import 'projects_provider.dart';

class ProjectsListScreen extends ConsumerWidget {
  const ProjectsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectsData = ref.watch(projectsProvider);
    final portfolio = ref.watch(portfolioSummaryProvider).valueOrNull;

    // Always render the screen shell (header + scrollable). Body swaps
    // between cached cards and skeletons — never blank.
    final projects = projectsData.valueOrNull;

    return Scaffold(
      backgroundColor: ArlColors.cream,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header — always rendered
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'YOUR PORTFOLIO',
                      style: TextStyle(
                        color: ArlColors.muted,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'All Projects',
                      style: TextStyle(
                        color: ArlColors.charcoal,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Builder(
                      builder: (_) {
                        final units = portfolio?.activeUnits ?? 0;
                        final invested = portfolio?.totalInvested ?? 0;
                        final count = projects?.length ?? 0;
                        return Text(
                          '$count ${count == 1 ? 'Project' : 'Projects'} · '
                          '$units ${units == 1 ? 'Unit' : 'Units'} · '
                          '${Money.inr(invested, inline: true)} invested',
                          style: const TextStyle(
                            color: ArlColors.muted,
                            fontSize: 11,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),

              // Body — cards if data, skeleton if not.
              if (projects == null)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    children: [
                      SkelBox(height: 120, margin: EdgeInsets.only(bottom: 12)),
                      SkelBox(height: 120, margin: EdgeInsets.only(bottom: 12)),
                      SkelBox(height: 120),
                    ],
                  ),
                )
              else
                ...projects.map((project) {
                  final gradientColor = _parseColor(project.colorHex);

                  return GestureDetector(
                    onTap: () => context.push('/projects/${project.id}'),
                    child: Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
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
                          // Header strip with gradient
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  gradientColor,
                                  gradientColor.withValues(alpha: 0.7),
                                ],
                              ),
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(15),
                                topRight: Radius.circular(15),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Initials circle
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Center(
                                    child: Text(
                                      project.initials,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),

                                // Name and location
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        project.name,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12,
                                        ),
                                      ),
                                      Text(
                                        '${project.location} · Month ${project.monthOfContract}',
                                        style: TextStyle(
                                          color: Colors.white
                                              .withValues(alpha: 0.8),
                                          fontSize: 10,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // Status badge
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: project.status == 'operational'
                                        ? ArlColors.accent
                                            .withValues(alpha: 0.25)
                                        : ArlColors.earth
                                            .withValues(alpha: 0.25),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    project.status == 'operational'
                                        ? 'Active'
                                        : 'Pending',
                                    style: TextStyle(
                                      color: project.status == 'operational'
                                          ? ArlColors.accent
                                          : ArlColors.earth,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Body
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Progress section
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Contract Progress',
                                      style: TextStyle(
                                        color: ArlColors.muted,
                                        fontSize: 10,
                                      ),
                                    ),
                                    Text(
                                      '${project.progressPercent.toInt()}%',
                                      style: const TextStyle(
                                        color: ArlColors.primary,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(3),
                                  child: LinearProgressIndicator(
                                    value: project.progressPercent / 100,
                                    minHeight: 6,
                                    backgroundColor: ArlColors.sand,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      gradientColor,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),

                                // Stats grid
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Consumer(
                                      builder: (context, ref2, _) {
                                        // One bulk query, then per-card
                                        // lookup. Replaces N parallel
                                        // investorAllocationProvider(id)
                                        // calls that were silently
                                        // returning null on cold mount.
                                        final allUnits = ref2
                                            .watch(investorUnitsListProvider)
                                            .valueOrNull;
                                        InvestorUnit? iu;
                                        if (allUnits != null) {
                                          for (final u in allUnits) {
                                            if (u.projectId == project.id) {
                                              iu = u;
                                              break;
                                            }
                                          }
                                        }
                                        final units =
                                            iu?.issuedUnits.toString() ?? '—';
                                        final invested = iu == null
                                            ? '—'
                                            : Money.inr(
                                                iu.capitalInvested +
                                                    iu.tokenAdvanceAmount,
                                                inline: true,
                                              );
                                        return Row(
                                          children: [
                                            Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                const Text(
                                                  'Your Units',
                                                  style: TextStyle(
                                                    color: ArlColors.muted,
                                                    fontSize: 9,
                                                  ),
                                                ),
                                                Text(
                                                  units,
                                                  style: const TextStyle(
                                                    color: ArlColors.charcoal,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(width: 16),
                                            Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                const Text(
                                                  'Invested',
                                                  style: TextStyle(
                                                    color: ArlColors.muted,
                                                    fontSize: 9,
                                                  ),
                                                ),
                                                Text(
                                                  invested,
                                                  style: const TextStyle(
                                                    color: ArlColors.charcoal,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Crop',
                                          style: TextStyle(
                                            color: ArlColors.muted,
                                            fontSize: 9,
                                          ),
                                        ),
                                        Text(
                                          project.cropEmoji,
                                          style: const TextStyle(
                                            fontSize: 16,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),

                                // Bottom row
                                if (project.status == 'pending')
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: ArlColors.earth
                                          .withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: ArlColors.earth
                                            .withValues(alpha: 0.3),
                                      ),
                                    ),
                                    child: const Row(
                                      children: [
                                        Icon(
                                          Icons.warning_amber_rounded,
                                          color: ArlColors.earth,
                                          size: 14,
                                        ),
                                        SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            '₹12L payment pending — payouts on hold',
                                            style: TextStyle(
                                              color: ArlColors.earth,
                                              fontSize: 9,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                else
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Next: ${Money.inr(project.nextPayoutAmount)} · ${project.nextPayoutDate != null ? DateFormat('MMM dd').format(project.nextPayoutDate!) : 'N/A'}',
                                        style: const TextStyle(
                                          color: ArlColors.muted,
                                          fontSize: 10,
                                        ),
                                      ),
                                      const Text(
                                        'View →',
                                        style: TextStyle(
                                          color: ArlColors.primary,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Color _parseColor(String hexColor) {
    hexColor = hexColor.replaceAll('#', '');
    return Color(int.parse('FF$hexColor', radix: 16));
  }
}
