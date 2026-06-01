import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:arl_app/core/constants/supabase_constants.dart';
import 'package:arl_app/core/navigation/route_names.dart';
import 'package:arl_app/core/theme/arl_colors.dart';
import 'package:arl_app/core/widgets/arl_app_bar.dart';
import 'package:arl_app/core/widgets/demo_badge.dart';
import 'package:arl_app/core/widgets/dev_bypass_banner.dart';
import 'package:arl_app/core/widgets/offline_banner.dart';
import 'package:arl_app/core/version/version_banner.dart';
import 'package:arl_app/features/onboarding/tour_arrow_overlay.dart';
import 'package:arl_app/features/onboarding/tour_controller.dart';
import 'package:arl_app/features/onboarding/tour_keys.dart';
import 'package:arl_app/features/projects/projects_provider.dart';

class MainScaffold extends ConsumerWidget {
  final Widget child;
  const MainScaffold({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;
    final currentIndex = _indexForRoute(location);

    // We surface the demo banner at the scaffold level so every screen
    // gets it for free. Logic: if any project the user has access to
    // is a demo row, the whole UI is sample-mode.
    final projects = ref.watch(projectsProvider).valueOrNull ?? const [];
    final inDemoMode = projects.any((p) => p.isDemo);

    // Auto-start the new arrow tour once per device: triggers when the
    // user lands in the shell and hasn't seen it. The gate is async
    // (reads `arl_tour_seen_v2` from secure storage) so we explicitly
    // ignore loading/error here — if storage is unreachable we'd
    // rather skip the auto-start than show the tour every launch on a
    // partial read. Once persisted state resolves to `false`, the
    // post-frame callback flips the tour on exactly once.
    final autoStartAsync = ref.watch(tourShouldAutoStartProvider);
    final tourActive = ref.watch(tourActiveProvider);
    autoStartAsync.whenData((shouldStart) {
      if (!shouldStart) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Re-check inside the frame so a fast state flip doesn't
        // double-start the tour.
        if (!ref.read(tourActiveProvider)) {
          startTour(ref, isAutoStart: true);
        }
      });
    });

    // The tour overlay is hoisted OUT of Scaffold.body so its painting
    // canvas spans the entire screen (AppBar + body + bottomNavigationBar
    // included). Inside the body, [RenderBox.localToGlobal] would return
    // global screen coords while the painter's local space starts at the
    // top of the body — the two diverge by the AppBar's height and the
    // cutout/arrow land in the wrong place (e.g. on the row below the
    // bell). Wrapping the Scaffold in a top-level Stack keeps the
    // overlay's local space = global screen space, so cutouts on AppBar
    // and bottomNavigationBar widgets paint where the user actually sees
    // them.
    final scaffold = Scaffold(
      backgroundColor: ArlColors.cream,
      appBar: const ArlAppBar(),
      body: Column(
        children: [
          const OfflineBanner(),
          if (SupabaseConstants.devBypassAuth) const DevBypassBanner(),
          DemoModeBanner(show: inDemoMode),
          const VersionBanner(),
          Expanded(child: child),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE1DFC6), width: 1)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 64,
            child: Row(
              children: [
                _NavItem(
                  key: TourKeys.bottomNavHome,
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home,
                  label: 'Home',
                  isActive: currentIndex == 0,
                  onTap: () => context.go(RouteNames.home),
                ),
                _NavItem(
                  key: TourKeys.bottomNavProjects,
                  icon: Icons.eco_outlined,
                  activeIcon: Icons.eco,
                  label: 'Projects',
                  isActive: currentIndex == 1,
                  onTap: () => context.go(RouteNames.projects),
                ),
                _NavItem(
                  key: TourKeys.bottomNavFinancials,
                  icon: Icons.bar_chart_outlined,
                  activeIcon: Icons.bar_chart,
                  label: 'Financials',
                  isActive: currentIndex == 2,
                  onTap: () => context.go(RouteNames.financials),
                ),
                _NavItem(
                  key: TourKeys.bottomNavExplore,
                  icon: Icons.explore_outlined,
                  activeIcon: Icons.explore,
                  label: 'Explore',
                  isActive: currentIndex == 3,
                  onTap: () => context.go(RouteNames.explore),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // Stack the overlay above the entire Scaffold so its painting space
    // matches the screen's global coordinate space. See the comment
    // above the Scaffold construction for the geometry rationale.
    if (!tourActive) return scaffold;
    return Stack(
      children: [
        scaffold,
        const Positioned.fill(child: TourArrowOverlay()),
      ],
    );
  }

  int _indexForRoute(String location) {
    if (location.startsWith(RouteNames.projects)) return 1;
    if (location.startsWith(RouteNames.financials)) return 2;
    if (location.startsWith(RouteNames.explore)) return 3;
    return 0;
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _NavItem({
    super.key,
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isActive ? activeIcon : icon,
              size: 24,
              color: isActive ? ArlColors.primary : ArlColors.muted,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive ? ArlColors.primary : ArlColors.muted,
              ),
            ),
            const SizedBox(height: 2),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: isActive ? 20 : 0,
              height: 3,
              decoration: BoxDecoration(
                color: ArlColors.gold,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
