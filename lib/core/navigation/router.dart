import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'route_names.dart';
import 'package:arl_app/core/widgets/main_scaffold.dart';
import 'package:arl_app/core/auth/session_manager.dart';
import 'package:arl_app/features/auth/auth_provider.dart';
import 'package:arl_app/features/home/home_screen.dart';
import 'package:arl_app/features/projects/projects_list_screen.dart';
import 'package:arl_app/features/projects/project_detail_screen.dart';
import 'package:arl_app/features/projects/location_screen.dart';
import 'package:arl_app/features/projects/project_selector_screen.dart';
import 'package:arl_app/features/financials/financials_screen.dart';
import 'package:arl_app/features/explore/explore_screen.dart';
import 'package:arl_app/features/gallery/gallery_screen.dart';
import 'package:arl_app/features/documents/documents_screen.dart';
import 'package:arl_app/features/activity/activity_screen.dart';
import 'package:arl_app/features/profile/profile_screen.dart';
import 'package:arl_app/features/profile/kyc_screen.dart';
import 'package:arl_app/features/profile/bank_details_screen.dart';
import 'package:arl_app/features/profile/security_screen.dart';
import 'package:arl_app/features/support/support_screen.dart';
import 'package:arl_app/features/support/ticket_detail_screen.dart';
import 'package:arl_app/features/support/new_ticket_screen.dart';
import 'package:arl_app/features/exit/exit_screen.dart';
import 'package:arl_app/features/auth/auth_screen.dart';
import 'package:arl_app/features/auth/biometric_screen.dart';
import 'package:arl_app/features/auth/login_screen.dart';
import 'package:arl_app/features/auth/setup_screen.dart';

/// Routes that don't require auth — visible to anonymous users.
const _publicRoutes = <String>{
  RouteNames.auth,
  RouteNames.login,
  RouteNames.setup,
};

/// B.T3: GoRouterRefreshStream — listens to a Stream and notifies GoRouter
/// to re-evaluate redirects when the stream emits.
class GoRouterRefreshStream extends ChangeNotifier {
  late final StreamSubscription<dynamic> _subscription;

  GoRouterRefreshStream(Stream<dynamic> stream) {
    _subscription = stream.listen((_) => notifyListeners());
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  // B.T3: Wire auth state changes to router refresh.
  final refreshNotifier =
      GoRouterRefreshStream(SessionManager.authStateChanges);

  return GoRouter(
    initialLocation: RouteNames.home,
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final isLoggedIn = ref.read(isLoggedInProvider);
      final loc = state.matchedLocation;
      final isPublic = _publicRoutes.contains(loc);

      // Not signed in + heading to a private route → bounce to /auth.
      if (!isLoggedIn && !isPublic) return RouteNames.auth;
      // Already signed in + on an auth route → bounce to home.
      if (isLoggedIn && isPublic) return RouteNames.home;
      return null;
    },
    routes: [
      // Auth (no bottom nav)
      GoRoute(
        path: RouteNames.auth,
        builder: (context, state) => const AuthScreen(),
      ),
      GoRoute(
        path: RouteNames.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: RouteNames.setup,
        builder: (context, state) => const InitialSetupScreen(),
      ),
      // Biometric verification — full-screen, no bottom nav. Pushed
      // from SecurityScreen as an enrollment/confirmation step; pops
      // with `true` on success, `false` on cancel.
      GoRoute(
        path: RouteNames.biometric,
        builder: (context, state) => const BiometricScreen(),
      ),

      // Main shell — all screens with bottom nav
      ShellRoute(
        builder: (context, state, child) => MainScaffold(child: child),
        routes: [
          GoRoute(
            path: RouteNames.home,
            builder: (context, state) => const HomeScreen(),
          ),
          GoRoute(
            path: RouteNames.projects,
            builder: (context, state) => const ProjectsListScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (context, state) => ProjectDetailScreen(
                  projectId: state.pathParameters['id'] ?? '',
                ),
              ),
            ],
          ),
          GoRoute(
            path: RouteNames.financials,
            builder: (context, state) => const FinancialsScreen(),
          ),
          GoRoute(
            path: RouteNames.explore,
            builder: (context, state) => const ExploreScreen(),
          ),
          GoRoute(
            path: RouteNames.gallery,
            builder: (context, state) => const GalleryScreen(),
          ),
          GoRoute(
            path: RouteNames.documents,
            builder: (context, state) => const DocumentsScreen(),
          ),
          GoRoute(
            path: RouteNames.activity,
            builder: (context, state) => const ActivityScreen(),
          ),
          GoRoute(
            path: RouteNames.profile,
            builder: (context, state) => const ProfileScreen(),
          ),
          GoRoute(
            path: RouteNames.kyc,
            builder: (context, state) => const KycScreen(),
          ),
          GoRoute(
            path: RouteNames.bankDetails,
            builder: (context, state) => const BankDetailsScreen(),
          ),
          GoRoute(
            path: RouteNames.security,
            builder: (context, state) => const SecurityScreen(),
          ),
          GoRoute(
            path: RouteNames.support,
            builder: (context, state) => const SupportScreen(),
          ),
          GoRoute(
            path: RouteNames.newTicket,
            builder: (context, state) => const NewTicketScreen(),
          ),
          GoRoute(
            path: RouteNames.exit,
            builder: (context, state) => const ExitScreen(),
          ),
          GoRoute(
            path: RouteNames.projectSelector,
            builder: (context, state) => const ProjectSelectorScreen(),
          ),
          GoRoute(
            path: '/location/:projectId',
            builder: (context, state) => LocationScreen(
              projectId: state.pathParameters['projectId'] ?? '',
            ),
          ),
          GoRoute(
            path: '/ticket/:ticketId',
            builder: (context, state) => TicketDetailScreen(
              ticketId: state.pathParameters['ticketId'] ?? '',
            ),
          ),
        ],
      ),
    ],
  );
});
