import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:arl_app/core/navigation/route_names.dart';
import 'package:arl_app/core/theme/arl_colors.dart';
import 'package:arl_app/core/widgets/skel_box.dart';
import 'package:arl_app/core/widgets/async_value_widget.dart';
import 'package:arl_app/features/financials/financials_provider.dart';
import 'package:arl_app/features/home/home_provider.dart';
import 'package:arl_app/features/home/models/portfolio_summary.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arl_app/features/onboarding/tour_keys.dart';
import 'package:arl_app/features/projects/projects_provider.dart';
import 'widgets/portfolio_card.dart';
import 'widgets/project_progress_card.dart';
import 'widgets/quick_stats_row.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // TODO: integration: call CelebrationTrigger.maybeShow(context, ref) here. See lib/features/celebration/README_FOR_T4.md
    // Use the scoped provider so picking a single project on the home
    // page filters Total Portfolio Value, Invested, Returns, Active
    // Units, etc. to that project. With selection cleared (All
    // Projects) it returns the global portfolio unchanged.
    final portfolioData = ref.watch(scopedPortfolioProvider);
    // Greeting / investor name should always come from the global
    // portfolio so it doesn't blank out on project switches.
    final globalName =
        ref.watch(portfolioSummaryProvider).valueOrNull?.investorName ??
            portfolioData.valueOrNull?.investorName ??
            '';
    final selectedProject = ref.watch(selectedProjectProvider);
    final greetingName = _greetingName(globalName);

    return Scaffold(
      backgroundColor: ArlColors.cream,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Welcome row + project selector pill (HTML parity)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Constrain the greeting column so a long name can't
                    // shove the project-selector pill off-screen.
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'WELCOME BACK',
                            style: TextStyle(
                              color: ArlColors.muted,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          // While the portfolio provider is still
                          // resolving, greetingName is empty — render a
                          // skeleton instead of a "Investor" placeholder
                          // that flashes on every cold load.
                          if (greetingName.isEmpty)
                            const SkelBox(height: 22, width: 140)
                          else
                            Text(
                              greetingName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: ArlColors.charcoal,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: () => context.push(RouteNames.projectSelector),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: ArlColors.sand,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.location_on_outlined,
                                color: ArlColors.primary, size: 14),
                            const SizedBox(width: 6),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 100),
                              child: Text(
                                selectedProject?.name ?? 'All Projects',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: ArlColors.charcoal,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.keyboard_arrow_down,
                                color: ArlColors.muted, size: 14),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Portfolio Card ───────────────────────────────────────
              // UX rule: keep showing the last known portfolio while a
              // refetch is in flight. Repos already return cached data
              // on failure; if even that's empty we fall back to a
              // zero-state PortfolioSummary, never a raw error.
              _buildPortfolioCluster(portfolioData, ref),
            ],
          ),
        ),
      ),
    );
  }

  /// Renders the portfolio + progress + stats cluster. Pulls cached
  /// data through reloads + errors so the screen never blanks once we
  /// have a value. Falls back to skeleton only on cold start.
  Widget _buildPortfolioCluster(
      AsyncValue<PortfolioSummary> async, WidgetRef ref) {
    final cached = async.valueOrNull;
    if (cached != null) {
      return Column(
        children: [
          PortfolioCard(key: TourKeys.portfolioCard, portfolio: cached),
          const SizedBox(height: 12),
          ProjectProgressCard(key: TourKeys.projectProgressCard),
          const SizedBox(height: 12),
          QuickStatsRow(key: TourKeys.quickStatsRow, portfolio: cached),
          const SizedBox(height: 24),
        ],
      );
    }
    // Defensive: the portfolio providers swallow failures into a
    // zero-state summary, so this rarely fires — but if an error ever
    // surfaces with no cached value, show a friendly retry card rather
    // than an endless skeleton.
    if (async.hasError) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: ErrorRetryView(
          onRetry: () {
            ref.invalidate(portfolioSummaryProvider);
            ref.invalidate(scopedPortfolioProvider);
          },
        ),
      );
    }
    return const _HomeSkeleton();
  }

  /// Returns the first name when available, otherwise the trimmed full
  /// name. Returns an empty string while the portfolio provider is
  /// still resolving — caller renders a skeleton in that case rather
  /// than a "Investor" placeholder that flashes on every cold load.
  ///
  /// Why first-name only: real investors often have multi-word names
  /// (e.g. "Test Person Test last") that overflow the greeting row and
  /// shove the project selector pill off-screen. The full name is still
  /// shown on the Profile tab, which has dedicated space for it.
  String _greetingName(String fullName) {
    final trimmed = fullName.trim();
    if (trimmed.isEmpty) return '';
    final firstWord = trimmed.split(RegExp(r'\s+')).first;
    if (firstWord.isEmpty) return '';
    // Capitalise first letter, leave the rest as the user typed it.
    return firstWord[0].toUpperCase() + firstWord.substring(1);
  }
}

/// Lightweight skeleton stand-in for the home portfolio cluster.
/// Same vertical rhythm as the real PortfolioCard + ProjectProgressCard
/// so the layout doesn't jump when data arrives. Shown while the first
/// fetch is in flight or as a fallback when no cached data exists yet.
class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          _skel(height: 200, radius: 15),
          const SizedBox(height: 12),
          _skel(height: 140, radius: 15),
          const SizedBox(height: 12),
          _skel(height: 80, radius: 15),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _skel({required double height, double radius = 12}) {
    return Container(
      width: double.infinity,
      height: height,
      decoration: BoxDecoration(
        color: ArlColors.sand.withOpacity(0.5),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
