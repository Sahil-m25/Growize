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
import 'package:arl_app/features/onboarding/tutorial_overlay.dart';
import 'package:arl_app/features/onboarding/tutorial_provider.dart';
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

    final showTutorial = ref.watch(shouldShowTutorialProvider);

    return Scaffold(
      backgroundColor: ArlColors.cream,
      appBar: const ArlAppBar(),
      body: Stack(
        children: [
          Column(
            children: [
              const OfflineBanner(),
              if (SupabaseConstants.devBypassAuth) const DevBypassBanner(),
              DemoModeBanner(show: inDemoMode),
              Expanded(child: child),
            ],
          ),
          if (showTutorial)
            const Positioned.fill(child: TutorialOverlay()),
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
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home,
                  label: 'Home',
                  isActive: currentIndex == 0,
                  onTap: () => context.go(RouteNames.home),
                ),
                _NavItem(
                  icon: Icons.eco_outlined,
                  activeIcon: Icons.eco,
                  label: 'Projects',
                  isActive: currentIndex == 1,
                  onTap: () => context.go(RouteNames.projects),
                ),
                _NavItem(
                  icon: Icons.bar_chart_outlined,
                  activeIcon: Icons.bar_chart,
                  label: 'Financials',
                  isActive: currentIndex == 2,
                  onTap: () => context.go(RouteNames.financials),
                ),
                _NavItem(
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
