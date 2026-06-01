import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:arl_app/core/navigation/route_names.dart';
import 'package:arl_app/core/theme/arl_colors.dart';
import 'package:arl_app/core/utils/money.dart';
import 'package:arl_app/features/documents/document_viewer_screen.dart';
import 'package:arl_app/features/documents/documents_provider.dart';
import 'package:arl_app/features/documents/models/document.dart';
import 'package:arl_app/features/documents/models/project_document.dart';
import 'package:arl_app/features/financials/financials_provider.dart';
import 'package:arl_app/features/financials/models/payout.dart';
import 'package:arl_app/features/projects/models/investor_unit.dart';
import 'package:arl_app/features/projects/models/project.dart';
import 'package:arl_app/features/projects/models/project_phase.dart';
import 'package:arl_app/features/projects/models/project_update.dart';
import 'package:arl_app/features/projects/widgets/phase_timeline_6.dart';
import 'package:arl_app/features/projects/widgets/project_action_tiles.dart';
import 'package:arl_app/features/projects/widgets/project_hero_banner.dart';
import 'package:arl_app/features/projects/widgets/project_stats_grid.dart';
import 'projects_provider.dart';

/// Project detail — the lean v3 "overview" page.
///
/// Mirrors the `projects-{gv|so|va}-view` blocks in the v2 mockup, with
/// the heavy geography + photos blocks moved out to dedicated sub-screens:
///   • View Area  → `/projects/<id>/view-area` — map, growing tech, crops,
///                 climate, acreage. See [ProjectViewAreaScreen].
///   • Photos     → `/projects/<id>/photos`    — per-project grid + zoom.
///   • Documents  → top-level `/documents` route.
///
/// Order on this screen:
///   1. [ProjectHeroBanner]          — 200 px photo + tier badge + name
///   2. [ProjectStatsGrid]           — Your Investment 2×2 grid
///   3. Current Phase tile + [PhaseTimeline6]
///   4. Recent Payouts mini-list (top 3 with "View all" → /financials)
///   5. [ProjectActionTiles]         — View Area · Photos · Documents
///   6. Monthly Updates accordion    — kept (progress narrative)
///   7. Single-line projection callout
///   8. Share Project (stub — T2 modal lands later)
///   9. Request Exit (if eligible)
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
  Color _hexToColor(String hex) {
    final h = hex.replaceAll('#', '');
    return Color(int.parse('FF$h', radix: 16));
  }

  /// Maps the project's progress to one of ten fixed stages (Zoho
  /// project_phases taxonomy). The real source of truth is the
  /// `project_phases` rows synced from Zoho; this heuristic is a
  /// transitional fallback until that join is wired.
  ///
  /// Heuristic: 0% → stage 0 (Land Closed), 100% → stage 9 (Go-live).
  /// Pending projects clamp to stage 0 regardless of progress so the
  /// timeline reads as "nothing started" until allocation clears.
  int _stageIndexFor(Project project) {
    final isPending = project.status.toLowerCase().contains('pending');
    if (isPending) return 0;
    final pct = project.progressPercent.clamp(0, 100);
    return (pct / 100 * 9).round().clamp(0, 9);
  }

  /// Build the 10-element started/completed list the timeline reads.
  ///
  /// Source order of preference:
  ///   1. Real `project_phases` rows from Supabase — mapped to stages
  ///      by `sort_order` (clamped to 0..9). `started_at`/`completed_at`
  ///      (migration 053) win over the legacy `phase_date` column.
  ///   2. Synthetic fallback derived from `project.startDate` for
  ///      done/current stages — keeps the demo (Pineapple LLP) showing
  ///      something useful until real Zoho phase rows land.
  ///
  /// Pending projects (no contract yet) return an all-null list so the
  /// timeline renders no date affordances.
  List<PhaseStageDates?> _phaseDatesFor(
    Project project,
    List<ProjectPhase> phases,
    int stageIdx,
  ) {
    final result = List<PhaseStageDates?>.filled(
      PhaseTimeline6.stageCount,
      null,
    );

    final isPending = project.status.toLowerCase().contains('pending');
    if (isPending) return result;

    // 1) Real phase rows — accept anything that maps into 0..9.
    var anyReal = false;
    for (final p in phases) {
      final idx = p.sortOrder.clamp(0, PhaseTimeline6.stageCount - 1);
      final s = p.effectiveStartedAt;
      final c = p.effectiveCompletedAt;
      if (s == null && c == null) continue;
      result[idx] = PhaseStageDates(startedAt: s, completedAt: c);
      anyReal = true;
    }
    if (anyReal) return result;

    // 2) Synthetic fallback — evenly space completed stages between
    // project.startDate and "now" so completed nodes get a visual
    // anchor date on demo projects. The current phase reports the
    // synthetic "started" date for the same slot.
    final start = project.startDate;
    final now = DateTime.now();
    if (!now.isAfter(start)) return result;

    final totalDays = now.difference(start).inDays;
    // Distribute completed stages (0..stageIdx-1) evenly across the
    // elapsed window; the current stage's start sits one slot later.
    final slots = (stageIdx + 1).clamp(1, PhaseTimeline6.stageCount);
    for (var i = 0; i < stageIdx && i < PhaseTimeline6.stageCount; i++) {
      final fraction = (i + 1) / slots;
      final at = start.add(Duration(days: (totalDays * fraction).round()));
      result[i] = PhaseStageDates(completedAt: at);
    }
    if (stageIdx < PhaseTimeline6.stageCount) {
      final fraction = stageIdx / slots;
      final at = start.add(Duration(days: (totalDays * fraction).round()));
      // Anchor the current phase's start either at the synthetic
      // fraction OR the project start (for stageIdx == 0) — whichever
      // is later, so the date never predates the contract launch.
      final startedAt = at.isBefore(start) ? start : at;
      result[stageIdx] = PhaseStageDates(startedAt: startedAt);
    }
    return result;
  }

  /// Demo image for the hero banner. Real photos come from
  /// `projects.marketplace_image` once Zoho is populated — see
  /// `docs/ops/data_sources_guide.md`. Falls back to initials inside
  /// the banner widget when the URL is null.
  String? _heroImageFor(Project project) {
    final id = project.id.replaceAll(RegExp(r'^demo:'), '').toLowerCase();
    switch (id) {
      case 'gv':
        return 'https://images.unsplash.com/photo-1530836369250-ef72a3f5cda8?w=900&q=80&auto=format&fit=crop';
      case 'so':
        return 'https://images.unsplash.com/photo-1559827260-dc66d52bef19?w=900&q=80&auto=format&fit=crop';
      case 'va':
        return 'https://images.unsplash.com/photo-1592982537447-7440770faae5?w=900&q=80&auto=format&fit=crop';
    }
    return null;
  }

  String _tierFor(Project project) {
    final t = project.cropType.toLowerCase();
    if (t.contains('premium')) return 'Premium';
    if (t.contains('standard')) return 'Standard';
    return 'Premium';
  }

  // _openShare removed — Share Project CTA on the detail screen was
  // dropped per UX feedback. Sharing happens at the portfolio level
  // (not per-project) in the current v3 model.

  @override
  Widget build(BuildContext context) {
    final projectData = ref.watch(projectByIdProvider(widget.projectId));

    return projectData.when(
      loading: () => const Scaffold(
        backgroundColor: ArlColors.cream,
        body: Center(child: CircularProgressIndicator()),
      ),
      // Repository falls back to cached data on errors; this branch is a
      // final safety net. Show the same loader so we never surface a raw
      // exception string.
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
        final stageIdx = _stageIndexFor(project);
        // Phases (milestone gates) and updates (monthly narrative posts)
        // are two different data sources. We watch both: phases feed the
        // started/completed date affordances on the timeline (falling
        // back to a synthetic schedule derived from project.startDate
        // when no rows are seeded yet); updates drive the Monthly
        // Updates accordion below.
        final phasesAsync = ref.watch(projectPhasesProvider(project.id));
        final phases = phasesAsync.valueOrNull ?? const <ProjectPhase>[];
        final phaseDates = _phaseDatesFor(project, phases, stageIdx);
        final updatesAsync = ref.watch(projectUpdatesProvider(project.id));
        final allocationAsync =
            ref.watch(investorAllocationProvider(project.id));
        final allocation = allocationAsync.valueOrNull;
        final payoutsAsync = ref.watch(payoutsProvider);

        return Scaffold(
          backgroundColor: ArlColors.cream,
          body: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1) Hero banner — 200px photo with gradient + tier badge.
                ProjectHeroBanner(
                  name: project.name,
                  location: project.location,
                  imageUrl: _heroImageFor(project),
                  tierBadge: _tierFor(project),
                  initials: project.initials,
                  fallbackTint: brand.withOpacity(0.35),
                  onBack: () {
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go(RouteNames.home);
                    }
                  },
                ),

                // 2) Your Investment stats grid.
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: ProjectStatsGrid(
                    project: project,
                    investor: allocation,
                  ),
                ),

                // 2b) Contract Progress bar — month X of Y + horizontal
                // bar, matches the HTML "Contract Progress line (slimmer)"
                // block. Hidden for pending projects (no contract yet).
                if (!isPending)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: _ContractProgressCard(project: project),
                  ),

                // 3) Current Phase + 6-stage timeline.
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: _CurrentPhaseCard(
                    currentStageIndex: stageIdx,
                    accent: brand,
                    phaseDates: phaseDates,
                  ),
                ),

                // 4) Action tiles — View Area · Photos.
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: ProjectActionTiles(
                    projectId: project.id,
                    photosLocked: isPending,
                    viewAreaTint: brand,
                  ),
                ),

                // Investment breakdown — surfaces the `investor_units` row
                // (capital + token + due + received) with the allocation
                // date. Only shown while capital is outstanding; once
                // everything is received the block stops being useful.
                if (allocation != null && allocation.capitalOutstanding > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: _InvestmentBreakdownCard(allocation: allocation),
                  ),

                // 5) Monthly Updates — narrative posts from Supabase.
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: _MonthlyUpdatesCard(updatesAsync: updatesAsync),
                ),

                // 6) Recent Payouts mini-list — moved BELOW Monthly Updates
                // per UX call. Top 3 + "View all" → financials.
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: _RecentPayoutsCard(
                    projectId: project.id,
                    payoutsAsync: payoutsAsync,
                    accent: brand,
                  ),
                ),

                // 7) Project Documents — horizontal-scrolling row backed
                // by `project_documents` (migration 054). Only renders
                // when the provider returns at least one row; empty
                // state stays off this screen to keep it lean.
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  child: _ProjectDocumentsCard(
                    projectId: project.id,
                    accent: brand,
                  ),
                ),

                // Share Project, Request Exit, and the Expected-Annual-
                // Return projection callout removed per UX call — share
                // happens at the LLP/portfolio level (not per-project),
                // exit is requested via Assistance, and the projection
                // line was duplicate with the Your Investment stats.
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Contract Progress card — "Contract Progress NN%" label, horizontal
/// gradient bar, and start / time-left / end markers underneath.
/// Mirrors the HTML "Contract Progress line (slimmer)" block.
class _ContractProgressCard extends StatelessWidget {
  final Project project;

  const _ContractProgressCard({required this.project});

  String _formatMonth(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month - 1]} ${d.year}';
  }

  String _timeLeft() {
    final now = DateTime.now();
    if (!project.endDate.isAfter(now)) return 'Contract complete';
    final monthsLeft =
        (project.endDate.year - now.year) * 12 +
            (project.endDate.month - now.month);
    if (monthsLeft <= 0) return 'Contract complete';
    final years = monthsLeft ~/ 12;
    final months = monthsLeft % 12;
    if (years == 0) return '$months mos left';
    if (months == 0) return '$years yr${years > 1 ? 's' : ''} left';
    return '$years yr${years > 1 ? 's' : ''} $months mos left';
  }

  @override
  Widget build(BuildContext context) {
    final pct = project.progressPercent.clamp(0, 100).toDouble();
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Contract Progress',
                style: TextStyle(
                  color: ArlColors.charcoal,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${pct.toStringAsFixed(0)}%',
                style: const TextStyle(
                  color: ArlColors.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              height: 8,
              color: ArlColors.sand,
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: pct / 100.0,
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [ArlColors.primary, ArlColors.accent],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatMonth(project.startDate),
                style: const TextStyle(color: ArlColors.muted, fontSize: 10),
              ),
              Text(
                _timeLeft(),
                style: const TextStyle(color: ArlColors.muted, fontSize: 10),
              ),
              Text(
                _formatMonth(project.endDate),
                style: const TextStyle(color: ArlColors.muted, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Current Phase tile — icon disc + label + "Stage N of 6" pill,
/// followed by the fixed 6-stage timeline.
class _CurrentPhaseCard extends StatelessWidget {
  final int currentStageIndex;
  final Color accent;
  final List<PhaseStageDates?> phaseDates;

  const _CurrentPhaseCard({
    required this.currentStageIndex,
    required this.accent,
    required this.phaseDates,
  });

  @override
  Widget build(BuildContext context) {
    final stageLabel = PhaseTimeline6.labelAt(currentStageIndex);

    // Compact card: padding tightened 14 → 10, header condensed into
    // one tight row (small disc + label + stage pill), and the timeline
    // gap shrunk to 6px so the whole block fits in ~180-220px on mobile.
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
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
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(Icons.eco_outlined, color: accent, size: 14),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: RichText(
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  text: TextSpan(
                    children: [
                      const TextSpan(
                        text: 'Current Phase  ',
                        style: TextStyle(
                          color: ArlColors.muted,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.4,
                        ),
                      ),
                      TextSpan(
                        text: stageLabel,
                        style: const TextStyle(
                          color: ArlColors.charcoal,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${currentStageIndex + 1}/${PhaseTimeline6.stageCount}',
                  style: TextStyle(
                    color: accent,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          PhaseTimeline6(
            currentStageIndex: currentStageIndex,
            accentOverride: accent,
            phaseDates: phaseDates,
          ),
        ],
      ),
    );
  }
}

/// Recent Payouts mini-list — top 3 most recent payouts scoped to this
/// project, plus a "View all" pill that jumps to the financials page.
class _RecentPayoutsCard extends StatelessWidget {
  final String projectId;
  final AsyncValue<List<Payout>> payoutsAsync;
  final Color accent;

  const _RecentPayoutsCard({
    required this.projectId,
    required this.payoutsAsync,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final all = payoutsAsync.valueOrNull ?? const <Payout>[];
    final mine = all.where((p) => p.projectId == projectId).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final recent = mine.take(3).toList();

    final df = DateFormat('MMM d, yyyy');

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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Recent Payouts',
                style: TextStyle(
                  color: ArlColors.charcoal,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              InkWell(
                onTap: () => context.push(RouteNames.financials),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: ArlColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'View all',
                        style: TextStyle(
                          color: ArlColors.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(Icons.arrow_forward,
                          size: 12, color: ArlColors.primary),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (recent.isEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: ArlColors.sand.withOpacity(0.4),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.payments_outlined,
                      size: 16, color: ArlColors.muted),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'No payouts yet — first credit lands after the next harvest.',
                      style:
                          TextStyle(color: ArlColors.muted, fontSize: 11),
                    ),
                  ),
                ],
              ),
            )
          else
            ...recent.map((p) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: ArlColors.accent.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: ArlColors.accent.withOpacity(0.1),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: ArlColors.accent.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.check_circle_outline,
                            size: 14,
                            color: ArlColors.accent,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                df.format(p.date),
                                style: const TextStyle(
                                  color: ArlColors.charcoal,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (p.utrRef != null)
                                Text(
                                  'UTR ${p.utrRef}',
                                  style: const TextStyle(
                                    color: ArlColors.muted,
                                    fontSize: 10,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Text(
                          '+${Money.inr(p.amount, inline: true)}',
                          style: const TextStyle(
                            color: ArlColors.gold,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                )),
        ],
      ),
    );
  }
}

/// Monthly Updates card — date-pill + title + body (+ optional cover
/// image) per row, sourced from `public.project_updates`. Limited to
/// 6 rows by the provider so the section stays scannable.
///
/// Loading state renders three skeleton cards; error / empty states
/// each render a single friendly placeholder so the section never
/// collapses to nothing.
class _MonthlyUpdatesCard extends StatelessWidget {
  final AsyncValue<List<ProjectUpdate>> updatesAsync;

  const _MonthlyUpdatesCard({required this.updatesAsync});

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
            'Monthly Updates',
            style: TextStyle(
              color: ArlColors.charcoal,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Field reports straight from the ground team.',
            style: TextStyle(color: ArlColors.muted, fontSize: 11),
          ),
          const SizedBox(height: 12),
          updatesAsync.when(
            loading: () => const _UpdatesSkeleton(),
            error: (_, __) => const _UpdatesInlineMessage(
              icon: Icons.error_outline,
              text: 'Could not load updates. Pull to refresh.',
            ),
            data: (updates) {
              if (updates.isEmpty) {
                return const _UpdatesInlineMessage(
                  icon: Icons.event_note_outlined,
                  text: 'No updates yet. Check back soon.',
                );
              }
              return Column(
                children: [
                  for (var i = 0; i < updates.length; i++) ...[
                    _UpdateRow(update: updates[i]),
                    if (i != updates.length - 1) const SizedBox(height: 10),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _UpdateRow extends StatelessWidget {
  final ProjectUpdate update;
  const _UpdateRow({required this.update});

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat('d MMM yyyy').format(update.updateDate);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ArlColors.cream,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ArlColors.sand),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: ArlColors.gold.withOpacity(0.18),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              dateLabel,
              style: const TextStyle(
                color: ArlColors.charcoal,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            update.title,
            style: const TextStyle(
              color: ArlColors.charcoal,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            update.body,
            style: const TextStyle(
              color: ArlColors.muted,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          if (update.imageUrl != null && update.imageUrl!.isNotEmpty) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(
                  update.imageUrl!,
                  fit: BoxFit.cover,
                  loadingBuilder: (_, child, progress) {
                    if (progress == null) return child;
                    return Container(color: ArlColors.sand);
                  },
                  errorBuilder: (_, __, ___) =>
                      Container(color: ArlColors.sand),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _UpdatesSkeleton extends StatelessWidget {
  const _UpdatesSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(3, (i) {
        return Padding(
          padding: EdgeInsets.only(bottom: i == 2 ? 0 : 10),
          child: Container(
            height: 78,
            decoration: BoxDecoration(
              color: ArlColors.sand.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }),
    );
  }
}

class _UpdatesInlineMessage extends StatelessWidget {
  final IconData icon;
  final String text;

  const _UpdatesInlineMessage({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ArlColors.sand.withOpacity(0.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: ArlColors.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: ArlColors.muted, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

// _ProjectionCallout removed — the Expected Annual Return line was
// duplicated by the Your Investment stats grid. Dropped per UX call.

class _InvestmentBreakdownCard extends StatelessWidget {
  final InvestorUnit allocation;
  const _InvestmentBreakdownCard({required this.allocation});

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd MMM yyyy');
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
            'Investment Breakdown',
            style: TextStyle(
              color: ArlColors.charcoal,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          _row('Capital Invested', Money.inr(allocation.capitalInvested)),
          _row('Token Advance', Money.inr(allocation.tokenAdvanceAmount)),
          _row('Outstanding', Money.inr(allocation.capitalOutstanding)),
          _row('Returns Received',
              Money.inr(allocation.totalAmountReceived)),
          const Divider(height: 16, color: ArlColors.sand),
          _row(
            'Allocation Date',
            allocation.investmentDate != null
                ? df.format(allocation.investmentDate!)
                : '—',
            dim: true,
          ),
          _row(
            'Annual Yield',
            '${_fmtPct(allocation.annualYieldPct)}%',
            dim: true,
          ),
        ],
      ),
    );
  }

  static String _fmtPct(double pct) =>
      pct.truncateToDouble() == pct ? pct.toStringAsFixed(0) : pct.toStringAsFixed(1);

  static Widget _row(String label, String value, {bool dim = false}) {
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
}

// _ShareButton and _RequestExitButton removed — both bottom CTAs were
// dropped from the detail page per UX call. Share modal still exists
// (used by Explore detail) but is no longer surfaced from owner-side
// project detail. Exit requests are routed via Assistance.

/// Project Documents card — horizontal-scrolling row of up to 4
/// document cards backed by `projectDocumentsProvider(projectId)`.
/// Renders nothing when the provider resolves empty so this screen
/// stays lean for projects with no docs uploaded yet (per spec).
///
/// "View all" pill at the end of the row pushes to the top-level
/// `/documents` route where the full list lives, grouped by project.
class _ProjectDocumentsCard extends ConsumerWidget {
  final String projectId;
  final Color accent;

  const _ProjectDocumentsCard({
    required this.projectId,
    required this.accent,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docsAsync = ref.watch(projectDocumentsProvider(projectId));
    final docs = docsAsync.valueOrNull ?? const <ProjectDocument>[];

    // Spec: don't render the section at all when empty. Loading and
    // error states are also collapsed -- the section evaporates until
    // there's something useful to show.
    if (docs.isEmpty) return const SizedBox.shrink();

    // Cap at 4 visible cards; "View all" handles the long tail.
    final visible = docs.take(4).toList();

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
          const Row(
            children: [
              Text(
                'Project Documents',
                style: TextStyle(
                  color: ArlColors.charcoal,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Agreements, brochures, and reports for this project.',
            style: TextStyle(color: ArlColors.muted, fontSize: 11),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              itemCount: visible.length + 1,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, idx) {
                if (idx == visible.length) {
                  return _ViewAllPill(
                    onTap: () => context.push(RouteNames.documents),
                  );
                }
                final doc = visible[idx];
                return _ProjectDocCardMini(doc: doc, accent: accent);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ProjectDocCardMini extends StatelessWidget {
  final ProjectDocument doc;
  final Color accent;

  const _ProjectDocCardMini({required this.doc, required this.accent});

  void _open(BuildContext context) {
    if (doc.signedUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Document URL unavailable')),
      );
      return;
    }
    final adapter = InvestorDocument(
      id: doc.id,
      name: doc.title,
      category: doc.category,
      visibility: 'project',
      projectId: doc.projectId,
      signedUrl: doc.signedUrl,
      uploadedAt: doc.uploadedAt,
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DocumentViewerScreen(
          documentId: doc.id,
          preloaded: adapter,
        ),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _open(context),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 150,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: ArlColors.cream,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ArlColors.sand),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.description_outlined, color: accent, size: 18),
            const SizedBox(height: 8),
            Text(
              doc.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: ArlColors.charcoal,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                (doc.category.isEmpty ? 'general' : doc.category).toUpperCase(),
                style: TextStyle(
                  color: accent,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ViewAllPill extends StatelessWidget {
  final VoidCallback onTap;
  const _ViewAllPill({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 110,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: ArlColors.primary.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: ArlColors.primary.withOpacity(0.25),
          ),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.folder_open_outlined,
                color: ArlColors.primary, size: 18),
            SizedBox(height: 8),
            Text(
              'View all',
              style: TextStyle(
                color: ArlColors.primary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'in Documents',
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

