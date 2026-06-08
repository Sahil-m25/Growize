import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:arl_app/core/theme/arl_colors.dart';
import 'package:arl_app/core/utils/money.dart';
import 'package:arl_app/core/widgets/skel_box.dart';
import 'package:arl_app/core/widgets/async_value_widget.dart';
import 'package:arl_app/features/home/home_provider.dart';
import 'package:arl_app/features/onboarding/tour_keys.dart';
import 'package:arl_app/features/projects/models/investor_unit.dart';
import 'package:arl_app/features/projects/models/project.dart';
import 'projects_provider.dart';

/// Projects list — 2-col tile grid matching HTML mockup `id="page-projects"`
/// (R4 redesign). Each tile has a 16:10 hero photo with status pill + tier
/// badge overlay, then a body block with crop chip, units owned, invested
/// amount, contract-progress bar, and a "Next payout" sub-line. Tapping a
/// tile pushes the project-detail route.
class ProjectsListScreen extends ConsumerWidget {
  const ProjectsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectsData = ref.watch(projectsProvider);
    final portfolio = ref.watch(portfolioSummaryProvider).valueOrNull;
    final unitsList = ref.watch(investorUnitsListProvider).valueOrNull;
    final projects = projectsData.valueOrNull;

    return Scaffold(
      backgroundColor: ArlColors.cream,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Eyebrow + title + summary line — wrapped in a Column
              // with TourKeys.projectsHeader so the tour overlay can
              // point at the whole portfolio header block.
              Column(
                key: TourKeys.projectsHeader,
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
                  const SizedBox(height: 4),
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
              const SizedBox(height: 16),
              // 3-stat strip (Active / Earned / Pending) removed per UX
              // call — the same data lives on Home dashboard and was
              // duplicate-noisy on this screen.

              // 2-col tile grid
              if (projectsData.hasError && projects == null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: ErrorRetryView(
                    message: 'We could not load your projects. '
                        "Tap retry once you're back online.",
                    onRetry: () => ref.invalidate(projectsProvider),
                  ),
                )
              else if (projects == null)
                const Column(
                  children: [
                    SkelBox(height: 230, margin: EdgeInsets.only(bottom: 12)),
                    SkelBox(height: 230, margin: EdgeInsets.only(bottom: 12)),
                  ],
                )
              else if (projects.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Text(
                      'No projects yet.',
                      style: TextStyle(color: ArlColors.muted, fontSize: 13),
                    ),
                  ),
                )
              else
                GridView.builder(
                  key: TourKeys.projectsGrid,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  // Adaptive: at narrow phone widths (~360-420px) gives
                  // 2 columns; at tablet widths (~768px) gives 3+. The
                  // childAspectRatio is tuned so the hero (16:10) plus
                  // the body block (crop chip + units row + progress
                  // bar + payout footer) fits without leaving an empty
                  // vertical gap at the bottom of the tile. Bumped from
                  // 0.95 → 0.87 (~8.5% taller) so the four body micro-
                  // rows sit more relaxed under the hero rather than
                  // looking cramped against the bottom edge.
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 220,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.87,
                  ),
                  itemCount: projects.length,
                  itemBuilder: (_, i) {
                    final project = projects[i];
                    InvestorUnit? iu;
                    if (unitsList != null) {
                      for (final u in unitsList) {
                        if (u.projectId == project.id) {
                          iu = u;
                          break;
                        }
                      }
                    }
                    return _ProjectTile(project: project, investorUnit: iu);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// _StatsStrip removed — Active/Earned/Pending tiles were dropped from
// the Projects list per UX call. The same numbers are visible on the
// Home dashboard and on per-project tiles, so the strip was duplicate.

/// A single project tile — hero photo + status + tier overlays, body with
/// crop chip, units, invested, progress bar, next-payout footer.
class _ProjectTile extends StatelessWidget {
  final Project project;
  final InvestorUnit? investorUnit;

  const _ProjectTile({required this.project, required this.investorUnit});

  /// Mock hero URL keyed by project id (lowercase, demo prefix stripped).
  /// Falls back to null → letter avatar inside the hero stack.
  String? get _heroUrl {
    final id = project.id.replaceAll(RegExp(r'^demo:'), '').toLowerCase();
    switch (id) {
      case 'gv':
      case 'eka':
        return 'https://images.unsplash.com/photo-1530836369250-ef72a3f5cda8?w=600&q=70&auto=format&fit=crop';
      case 'so':
        return 'https://images.unsplash.com/photo-1559827260-dc66d52bef19?w=600&q=70&auto=format&fit=crop';
      case 'va':
        return 'https://images.unsplash.com/photo-1592982537447-7440770faae5?w=600&q=70&auto=format&fit=crop';
    }
    return null;
  }

  String get _statusLabel {
    final s = project.status.toLowerCase();
    if (s.contains('pending')) return 'PENDING';
    if (s.contains('setup')) return 'SETUP';
    if (s.contains('operational') || s.contains('active')) return 'OPERATIONAL';
    return s.toUpperCase();
  }

  Color get _statusBg {
    final s = project.status.toLowerCase();
    if (s.contains('pending')) return ArlColors.earth;
    if (s.contains('setup')) return ArlColors.gold;
    return ArlColors.accent;
  }

  String get _tier {
    final t = project.cropType.toLowerCase();
    if (t.contains('standard')) return 'Standard';
    return 'Premium';
  }

  @override
  Widget build(BuildContext context) {
    final hero = project.id.isNotEmpty ? _heroUrl : null;
    final units = investorUnit?.issuedUnits.toString() ?? '—';
    final invested = investorUnit == null
        ? null
        : Money.inr(
            investorUnit!.capitalInvested + investorUnit!.tokenAdvanceAmount,
            inline: true,
          );
    final nextPayout = project.nextPayoutAmount > 0
        ? '${Money.inr(project.nextPayoutAmount, inline: true)} · ${project.nextPayoutDate != null ? DateFormat('MMM d').format(project.nextPayoutDate!) : ''}'
        : null;

    return InkWell(
      onTap: () => context.push('/projects/${project.id}'),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: ArlColors.sand),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero photo with overlays.
            AspectRatio(
              aspectRatio: 16 / 10,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (hero != null && hero.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: hero,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(color: ArlColors.sand),
                      errorWidget: (_, __, ___) =>
                          _letterAvatar(project.initials),
                    )
                  else
                    _letterAvatar(project.initials),
                  // Bottom gradient for legibility.
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.0, 0.5, 1.0],
                        colors: [
                          Colors.black.withOpacity(0.05),
                          Colors.transparent,
                          Colors.black.withOpacity(0.45),
                        ],
                      ),
                    ),
                  ),
                  // Status pill top-left
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: _statusBg,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _statusLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                  // Tier badge top-right
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.45),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.2),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _tier == 'Premium'
                                ? Icons.workspace_premium
                                : Icons.eco_outlined,
                            color: ArlColors.goldLight,
                            size: 10,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            _tier,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Name + location bottom-left
                  Positioned(
                    bottom: 6,
                    left: 6,
                    right: 6,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          project.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            shadows: [
                              Shadow(blurRadius: 4, color: Colors.black54),
                            ],
                          ),
                        ),
                        if (project.location.isNotEmpty)
                          Row(
                            children: [
                              const Icon(
                                Icons.location_on_outlined,
                                color: Colors.white,
                                size: 10,
                              ),
                              const SizedBox(width: 3),
                              Flexible(
                                child: Text(
                                  project.location,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    shadows: [
                                      Shadow(
                                          blurRadius: 3, color: Colors.black54),
                                    ],
                                  ),
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
            // Body — sized to content so the tile doesn't grow vertical
            // dead-space when the aspect ratio is wider than the content
            // needs. Internal padding tightened from 10 → 8 and the row
            // gaps reduced from 6 → 4 so the four micro-rows pack into
            // the available square-ish area.
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: ArlColors.sand,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (project.cropEmoji.isNotEmpty)
                              Text(project.cropEmoji,
                                  style: const TextStyle(fontSize: 10)),
                            if (project.cropEmoji.isNotEmpty)
                              const SizedBox(width: 4),
                            Text(
                              project.cropType.isNotEmpty
                                  ? project.cropType
                                  : 'Mixed crops',
                              style: const TextStyle(
                                color: ArlColors.charcoal,
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'Month ${project.monthOfContract}/${project.totalMonths}',
                        style: const TextStyle(
                            color: ArlColors.muted, fontSize: 9),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '$units ',
                        style: const TextStyle(
                          color: ArlColors.charcoal,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Text(
                        'Units',
                        style: TextStyle(
                          color: ArlColors.muted,
                          fontSize: 9,
                        ),
                      ),
                      const Spacer(),
                      if (invested != null)
                        Text(
                          invested,
                          style: const TextStyle(
                            color: ArlColors.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Contract progress micro-bar.
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      height: 4,
                      color: ArlColors.sand,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor:
                              (project.progressPercent / 100).clamp(0, 1),
                          child: Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [ArlColors.primary, ArlColors.accent],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (nextPayout != null)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Next payout',
                          style:
                              TextStyle(color: ArlColors.muted, fontSize: 9),
                        ),
                        Flexible(
                          child: Text(
                            nextPayout,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: ArlColors.accent,
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    const Text(
                      'Awaiting first payout',
                      style: TextStyle(color: ArlColors.muted, fontSize: 9),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _letterAvatar(String initials) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [ArlColors.primary, ArlColors.accent],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 28,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
