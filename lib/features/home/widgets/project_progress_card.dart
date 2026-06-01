import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:arl_app/core/navigation/route_names.dart';
import 'package:arl_app/core/theme/arl_colors.dart';
import 'package:arl_app/core/widgets/demo_badge.dart';
import 'package:arl_app/features/projects/models/project.dart';
import 'package:arl_app/features/projects/projects_provider.dart';

/// Mirrors HTML `progress-card`: switches between
/// `progress-single-view` (one project) and `progress-all-view`
/// (3 stacked mini bars labelled "Contract Progress").
class ProjectProgressCard extends ConsumerWidget {
  const ProjectProgressCard({super.key});

  static List<Color> _barFor(Project p) {
    final base = _hexToColor(p.colorHex);
    return [base, base.withOpacity(0.7)];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedId = ref.watch(selectedProjectIdProvider);
    final asyncProjects = ref.watch(projectsProvider);
    final showAll = selectedId == null;

    final projects = asyncProjects.valueOrNull;

    // Loading: still waiting on the first response — show spinner.
    if (projects == null) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(16),
        decoration: _cardDeco(),
        child: const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: CircularProgressIndicator(
              color: ArlColors.primary,
              strokeWidth: 2,
            ),
          ),
        ),
      );
    }

    // Resolved-but-empty: zero projects (or fetch fell back to empty).
    // Show an actionable empty state instead of an infinite spinner.
    if (projects.isEmpty) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(16),
        decoration: _cardDeco(),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Contract Progress',
              style: TextStyle(
                color: ArlColors.charcoal,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'No projects yet — your allocations will appear here once they sync.',
              style: TextStyle(color: ArlColors.muted, fontSize: 11),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: _cardDeco(),
      child: showAll
          ? _AllProjectsView(projects: projects)
          : _SingleProjectView(
              project: projects.firstWhere(
                (p) => p.id == selectedId,
                orElse: () => projects.first,
              ),
            ),
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

class _SingleProjectView extends StatelessWidget {
  final Project project;
  const _SingleProjectView({required this.project});

  @override
  Widget build(BuildContext context) {
    final isPending = project.status.toLowerCase().contains('pending');
    final bar = ProjectProgressCard._barFor(project);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          project.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: ArlColors.charcoal,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      DemoBadge(show: project.isDemo),
                    ],
                  ),
                  Text(
                    project.location,
                    style: const TextStyle(
                      color: ArlColors.muted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: (isPending ? ArlColors.earth : ArlColors.accent)
                    .withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                isPending ? 'Pending' : 'Operational',
                style: TextStyle(
                  color: isPending ? ArlColors.earth : ArlColors.accent,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Overall Progress',
              style: TextStyle(color: ArlColors.muted, fontSize: 11),
            ),
            Text(
              '${project.progressPercent.toInt()}%',
              style: const TextStyle(
                color: ArlColors.primary,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _GradientBar(value: project.progressPercent / 100, gradient: bar),
        const SizedBox(height: 8),
        Text(
          isPending
              ? 'Awaiting payment clearance'
              : 'Month ${project.monthOfContract} of ${project.totalMonths}',
          style: const TextStyle(color: ArlColors.muted, fontSize: 10),
        ),
        if (isPending) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: ArlColors.earth.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 12, color: ArlColors.earth),
                SizedBox(width: 6),
                Text(
                  'Payouts on hold — payment pending',
                  style: TextStyle(
                    color: ArlColors.earth,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: _ProjectsPill(
            label: 'View Project',
            // `context.go` matches the bottom-nav convention so the
            // Projects tab becomes the active root instead of stacking
            // on top of Home in the back-stack.
            onTap: () => context.go(RouteNames.projects),
          ),
        ),
      ],
    );
  }
}

class _AllProjectsView extends StatelessWidget {
  final List<Project> projects;
  const _AllProjectsView({required this.projects});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Contract Progress',
          style: TextStyle(
            color: ArlColors.charcoal,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        for (int i = 0; i < projects.length; i++) ...[
          _MiniProgress(project: projects[i]),
          if (i < projects.length - 1) const SizedBox(height: 12),
        ],
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: _ProjectsPill(
            label: 'View All Projects',
            onTap: () => context.go(RouteNames.projects),
          ),
        ),
      ],
    );
  }
}

/// Reusable pill CTA matching HTML
/// `text-xs text-arl-primary font-semibold bg-arl-primary/10 px-3 py-1.5 rounded-full`.
/// Used by both the single-project ("View Project") and all-projects
/// ("View All Projects") views inside [ProjectProgressCard].
class _ProjectsPill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _ProjectsPill({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: ArlColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: ArlColors.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.arrow_forward,
                color: ArlColors.primary,
                size: 14,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniProgress extends StatelessWidget {
  final Project project;
  const _MiniProgress({required this.project});

  @override
  Widget build(BuildContext context) {
    final isPending = project.status.toLowerCase().contains('pending');
    final bar = ProjectProgressCard._barFor(project);

    return Column(
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
                      project.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: ArlColors.charcoal,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  DemoBadge(show: project.isDemo),
                ],
              ),
            ),
            Text(
              '${project.progressPercent.toInt()}%',
              style: const TextStyle(
                color: ArlColors.primary,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        _GradientBar(value: project.progressPercent / 100, gradient: bar),
        const SizedBox(height: 2),
        Text(
          isPending
              ? 'Awaiting payment clearance · Pending'
              : 'Month ${project.monthOfContract} of ${project.totalMonths} · Operational',
          style: TextStyle(
            color: isPending ? ArlColors.earth : ArlColors.muted,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

class _GradientBar extends StatelessWidget {
  final double value;
  final List<Color> gradient;
  const _GradientBar({required this.value, required this.gradient});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Container(
        height: 8,
        color: ArlColors.sand,
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: value.clamp(0.0, 1.0),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: gradient),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Color _hexToColor(String hex) {
  final h = hex.replaceAll('#', '');
  return Color(int.parse('FF$h', radix: 16));
}
