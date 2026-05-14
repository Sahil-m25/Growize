import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:arl_app/core/navigation/route_names.dart';
import 'package:arl_app/core/theme/arl_colors.dart';
import 'package:arl_app/core/utils/money.dart';
import 'package:arl_app/features/projects/models/project_phase.dart';
import 'projects_provider.dart';

/// Mirrors HTML projects-{gv|so|va}-view per-project pages.
/// Hero gradient uses the project's brand colour, status pill switches
/// arl-accent (operational) vs arl-earth (pending), stats grid + phase
/// milestone timeline are driven by the selected project's mock data.
class ProjectDetailScreen extends ConsumerStatefulWidget {
  final String projectId;

  const ProjectDetailScreen({
    required this.projectId,
    super.key,
  });

  @override
  ConsumerState<ProjectDetailScreen> createState() =>
      _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends ConsumerState<ProjectDetailScreen> {
  final Set<int> _expandedPhases = {1};

  Color _phaseColor(String status) {
    switch (status) {
      case 'done':
        return ArlColors.accent;
      case 'active':
      case 'current':
        return ArlColors.gold;
      default:
        return ArlColors.muted;
    }
  }

  String _phaseLabel(String status) {
    switch (status) {
      case 'done':
        return 'DONE';
      case 'active':
      case 'current':
        return 'IN PROGRESS';
      default:
        return 'UPCOMING';
    }
  }

  Color _hexToColor(String hex) {
    final h = hex.replaceAll('#', '');
    return Color(int.parse('FF$h', radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    final projectData = ref.watch(projectByIdProvider(widget.projectId));

    return projectData.when(
      loading: () => const Scaffold(
        backgroundColor: ArlColors.cream,
        body: Center(child: CircularProgressIndicator()),
      ),
      // Repository falls back to cached data on errors; this branch is
      // a final safety net. Show the same loader silhouette as the
      // loading branch so we never surface a raw exception string.
      error: (_, __) => const Scaffold(
        backgroundColor: ArlColors.cream,
        body: Center(child: CircularProgressIndicator()),
      ),
      data: (project) {
        if (project == null) {
          return const Scaffold(
            backgroundColor: ArlColors.cream,
            body: Center(child: Text('Project not found')),
          );
        }

        final isPending = project.status.toLowerCase().contains('pending');
        final brand = _hexToColor(project.colorHex);
        final phasesAsync = ref.watch(projectPhasesProvider(project.id));
        final phases = phasesAsync.valueOrNull ?? const <ProjectPhase>[];
        final fmt = DateFormat('MMM yyyy');

        return Scaffold(
          backgroundColor: ArlColors.cream,
          body: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Hero(
                  initials: project.initials,
                  name: project.name,
                  location: project.location,
                  monthOfContract: project.monthOfContract,
                  totalMonths: project.totalMonths,
                  brand: brand,
                  isPending: isPending,
                  onBack: () {
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go(RouteNames.home);
                    }
                  },
                  onGallery: () => context.push(RouteNames.gallery),
                  onViewArea: () => context.push(
                    RouteNames.locationPath(widget.projectId),
                  ),
                ),
                // Investor-scoped stats — units owned and capital they
                // have invested, NOT project totals. Falls back to "—"
                // while the per-project allocation is loading or absent.
                Consumer(
                  builder: (context, ref, _) {
                    final iuAsync =
                        ref.watch(investorAllocationProvider(project.id));
                    final iu = iuAsync.valueOrNull;
                    final units = iu?.issuedUnits.toString() ?? '—';
                    final invested = iu == null
                        ? '—'
                        : Money.inr(
                            iu.capitalInvested + iu.tokenAdvanceAmount,
                            inline: true,
                          );
                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                          child: Row(
                            children: [
                              Expanded(
                                child: _StatTile(
                                  label: 'Your Units',
                                  value: units,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _StatTile(
                                  label: 'Month',
                                  value:
                                      '${project.monthOfContract}/${project.totalMonths}',
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _StatTile(
                                  label: 'Invested',
                                  value: invested,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (iu != null && iu.unitPrice > 0)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text.rich(
                                    TextSpan(
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: ArlColors.muted,
                                      ),
                                      children: [
                                        const TextSpan(text: 'Invested '),
                                        TextSpan(
                                          text: invested,
                                          style: const TextStyle(
                                            color: ArlColors.charcoal,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const TextSpan(text: '  ·  Per-unit '),
                                        TextSpan(
                                          text: Money.inr(iu.unitPrice,
                                              inline: true),
                                          style: const TextStyle(
                                            color: ArlColors.charcoal,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    );
                  },
                ),

                // Investment breakdown — surfaces the columns from the
                // investor's `investor_units` row (capital + token + due
                // + received) with the allocation date so the investor
                // can see how their money is split. Hidden when the
                // investor has no allocation in this project, OR once
                // all committed capital has been received (outstanding
                // is zero) — at that point the breakdown stops being
                // actionable info.
                Consumer(
                  builder: (context, ref, _) {
                    final iu = ref
                        .watch(investorAllocationProvider(project.id))
                        .valueOrNull;
                    if (iu == null) return const SizedBox.shrink();
                    if (iu.capitalOutstanding <= 0) {
                      return const SizedBox.shrink();
                    }
                    final df = DateFormat('dd MMM yyyy');
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: ArlColors.sand),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Investment Breakdown',
                              style: TextStyle(
                                color: ArlColors.charcoal,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 10),
                            _breakdownRow('Capital Invested',
                                Money.inr(iu.capitalInvested)),
                            _breakdownRow('Token Advance',
                                Money.inr(iu.tokenAdvanceAmount)),
                            _breakdownRow('Outstanding',
                                Money.inr(iu.capitalOutstanding)),
                            _breakdownRow('Returns Received',
                                Money.inr(iu.totalAmountReceived)),
                            const Divider(
                              height: 16,
                              color: ArlColors.sand,
                            ),
                            _breakdownRow(
                              'Allocation Date',
                              iu.investmentDate != null
                                  ? df.format(iu.investmentDate!)
                                  : '—',
                              dim: true,
                            ),
                            _breakdownRow(
                              'Annual Yield',
                              '${iu.annualYieldPct.toStringAsFixed(iu.annualYieldPct.truncateToDouble() == iu.annualYieldPct ? 0 : 1)}%',
                              dim: true,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: ArlColors.sand),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Contract Progress',
                              style: TextStyle(
                                color: ArlColors.charcoal,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '${project.progressPercent.toInt()}%',
                              style: const TextStyle(
                                color: ArlColors.primary,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Container(
                            height: 8,
                            color: ArlColors.sand,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: FractionallySizedBox(
                                widthFactor: (project.progressPercent / 100)
                                    .clamp(0.0, 1.0),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: brand,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              fmt.format(project.startDate),
                              style: const TextStyle(
                                  color: ArlColors.muted, fontSize: 10),
                            ),
                            Text(
                              fmt.format(project.endDate),
                              style: const TextStyle(
                                  color: ArlColors.muted, fontSize: 10),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                // Phase widgets retire 6 months after the first deposit
                // (investment_date on investor_units). Past that point
                // crop is well into operations and the phase tracker
                // adds noise rather than signal. When no allocation
                // row exists we keep the timeline visible so prospective
                // investors browsing the listing can still see scope.
                Consumer(
                  builder: (context, ref, _) {
                    final iu = ref
                        .watch(investorAllocationProvider(project.id))
                        .valueOrNull;
                    final cutoff =
                        iu?.investmentDate?.add(const Duration(days: 183));
                    final hidePhases =
                        cutoff != null && DateTime.now().isAfter(cutoff);
                    if (hidePhases) return const SizedBox(height: 24);
                    return Column(
                      children: [
                        if (phases.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                            child: _PhaseTimeline(phases: phases),
                          ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                          child: _ExpandablePhases(
                            phases: phases,
                            expanded: _expandedPhases,
                            onToggle: (idx) => setState(() {
                              _expandedPhases.contains(idx)
                                  ? _expandedPhases.remove(idx)
                                  : _expandedPhases.add(idx);
                            }),
                            phaseColor: _phaseColor,
                            phaseLabel: _phaseLabel,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Single label/value row used inside the Investment Breakdown card.
Widget _breakdownRow(String label, String value, {bool dim = false}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: dim ? ArlColors.muted : ArlColors.charcoal,
            fontSize: 11,
            fontWeight: dim ? FontWeight.w400 : FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: dim ? ArlColors.muted : ArlColors.charcoal,
            fontSize: 12,
            fontWeight: dim ? FontWeight.w500 : FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _Hero extends StatelessWidget {
  final String initials;
  final String name;
  final String location;
  final int monthOfContract;
  final int totalMonths;
  final Color brand;
  final bool isPending;
  final VoidCallback onBack;
  final VoidCallback onGallery;
  final VoidCallback onViewArea;

  const _Hero({
    required this.initials,
    required this.name,
    required this.location,
    required this.monthOfContract,
    required this.totalMonths,
    required this.brand,
    required this.isPending,
    required this.onBack,
    required this.onGallery,
    required this.onViewArea,
  });

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16, topInset + 8, 16, 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            brand,
            brand.withValues(alpha: 0.7),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: onBack,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Back',
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Back to All Projects',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.image_outlined, color: Colors.white),
                onPressed: onGallery,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Gallery',
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.35)),
                ),
                alignment: Alignment.center,
                child: Text(
                  initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$location · Month $monthOfContract of $totalMonths',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isPending ? ArlColors.earth : ArlColors.accent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  isPending ? 'Pending' : 'Operational',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: onViewArea,
                style: TextButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.16),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.map_outlined,
                    color: Colors.white, size: 14),
                label: const Text(
                  'View Area',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  const _StatTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: ArlColors.sand),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: ArlColors.muted,
              fontSize: 9,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: ArlColors.charcoal,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _PhaseTimeline extends StatelessWidget {
  final List<ProjectPhase> phases;
  const _PhaseTimeline({required this.phases});

  static String _shortDate(DateTime? d) {
    if (d == null) return '—';
    return DateFormat("MMM ''yy").format(d);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: ArlColors.sand),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'OPERATIONAL TIMELINE',
            style: TextStyle(
              color: ArlColors.muted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(phases.length, (idx) {
                final m = phases[idx];
                final isLast = idx == phases.length - 1;
                return Row(
                  children: [
                    Column(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: m.isDone ? ArlColors.accent : ArlColors.sand,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: m.isDone
                                  ? ArlColors.accent
                                  : ArlColors.muted.withValues(alpha: 0.3),
                              width: 1.5,
                            ),
                          ),
                          child: Icon(
                            m.isDone ? Icons.check : Icons.schedule,
                            size: 14,
                            color: m.isDone ? Colors.white : ArlColors.muted,
                          ),
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          width: 64,
                          child: Text(
                            m.name,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: m.isDone
                                  ? ArlColors.charcoal
                                  : ArlColors.muted,
                              fontSize: 9,
                              fontWeight: m.isDone
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _shortDate(m.phaseDate),
                          style: const TextStyle(
                              color: ArlColors.muted, fontSize: 8),
                        ),
                      ],
                    ),
                    if (!isLast)
                      Container(
                        width: 32,
                        height: 2,
                        margin: const EdgeInsets.only(bottom: 32),
                        decoration: BoxDecoration(
                          color: m.isDone
                              ? ArlColors.accent.withValues(alpha: 0.4)
                              : ArlColors.sand,
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                  ],
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpandablePhases extends StatelessWidget {
  final List<ProjectPhase> phases;
  final Set<int> expanded;
  final void Function(int) onToggle;
  final Color Function(String) phaseColor;
  final String Function(String) phaseLabel;

  const _ExpandablePhases({
    required this.phases,
    required this.expanded,
    required this.onToggle,
    required this.phaseColor,
    required this.phaseLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: ArlColors.sand),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'PROJECT PHASES',
            style: TextStyle(
              color: ArlColors.muted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            phases.isEmpty
                ? 'No phases recorded for this project yet'
                : 'Tap a phase to expand sub-tasks',
            style: const TextStyle(color: ArlColors.muted, fontSize: 10),
          ),
          const SizedBox(height: 10),
          if (phases.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  'Phase milestones will appear here once operations begin.',
                  style: TextStyle(color: ArlColors.muted, fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            ...List.generate(phases.length, (idx) {
              final phase = phases[idx];
              final isExpanded = expanded.contains(idx);
              final color = phaseColor(phase.status);
              final subItems = phase.subItems;

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: ArlColors.sand),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: subItems.isEmpty ? null : () => onToggle(idx),
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Row(
                          children: [
                            Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                phase.name,
                                style: const TextStyle(
                                  color: ArlColors.charcoal,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Text(
                              phaseLabel(phase.status),
                              style: TextStyle(
                                color: color,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                            if (subItems.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              AnimatedRotation(
                                turns: isExpanded ? 0.5 : 0,
                                duration: const Duration(milliseconds: 200),
                                child: const Icon(
                                  Icons.expand_more,
                                  size: 18,
                                  color: ArlColors.muted,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (isExpanded && subItems.isNotEmpty) ...[
                      const Divider(
                          height: 1, indent: 26, color: ArlColors.sand),
                      ...subItems.map((item) {
                        final label = (item['label'] ?? '').toString();
                        final status = (item['status'] ?? 'pending').toString();
                        final taskColor = phaseColor(status);
                        IconData taskIcon;
                        switch (status) {
                          case 'done':
                            taskIcon = Icons.check_circle;
                            break;
                          case 'active':
                          case 'current':
                            taskIcon = Icons.radio_button_checked;
                            break;
                          default:
                            taskIcon = Icons.radio_button_unchecked;
                        }
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(26, 6, 10, 6),
                          child: Row(
                            children: [
                              Icon(taskIcon, size: 14, color: taskColor),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  label,
                                  style: TextStyle(
                                    color: status == 'pending'
                                        ? ArlColors.muted
                                        : ArlColors.charcoal,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                      const SizedBox(height: 4),
                    ],
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}
