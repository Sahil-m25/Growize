import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'route_names.dart';
import 'package:arl_app/core/widgets/main_scaffold.dart';
import 'package:arl_app/core/auth/session_manager.dart';
import 'package:arl_app/features/home/home_screen.dart';
import 'package:arl_app/features/projects/projects_list_screen.dart';
import 'package:arl_app/features/projects/project_detail_screen.dart';
import 'package:arl_app/features/projects/project_photos_screen.dart';
import 'package:arl_app/features/projects/project_view_area_screen.dart';
import 'package:arl_app/features/projects/location_screen.dart';
import 'package:arl_app/features/projects/project_selector_screen.dart';
import 'package:arl_app/features/financials/financials_screen.dart';
import 'package:arl_app/features/explore/explore_screen.dart';
import 'package:arl_app/features/explore/explore_detail_screen.dart';
import 'package:arl_app/features/gallery/gallery_screen.dart';
import 'package:arl_app/features/documents/documents_screen.dart';
import 'package:arl_app/features/documents/document_viewer_screen.dart';
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
import 'package:arl_app/features/auth/otp_screen.dart';
import 'package:arl_app/features/auth/setup_biometric_screen.dart';
import 'package:arl_app/features/auth/setup_screen.dart';
import 'package:arl_app/features/legal/legal_document_screen.dart';
import 'package:arl_app/features/celebration/celebration_screen.dart';

/// Routes that don't require auth — visible to anonymous users.
const _publicRoutes = <String>{
  RouteNames.auth,
  RouteNames.login,
  // OTP entry is mid-flow: the user has submitted their email but
  // hasn't redeemed the code yet, so there's no session. Public so
  // the redirect doesn't bounce them back to /auth before they can
  // verify.
  RouteNames.otp,
  RouteNames.setup,
  RouteNames.privacy,
  RouteNames.terms,
};

/// Marketplace project detail (`/explore/<projectId>`) is reachable
/// without sign-in so links shared from the in-app Share Project modal
/// open cleanly in a new browser tab. The page itself reads
/// `MarketplaceProject` rows which are RLS-allowed for anon (they're
/// marketing data), and the consultation form gracefully prompts
/// sign-in if an anon user tries to submit.
bool _isPublicLocation(String loc) {
  if (_publicRoutes.contains(loc)) return true;
  if (loc.startsWith('/explore/') && loc.length > '/explore/'.length) {
    return true;
  }
  return false;
}

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
      // Read SessionManager directly (sync) instead of the Riverpod
      // Provider. The Provider value is cached until `authStateProvider`
      // emits, which lags behind `verifyOTP`'s await — causing a
      // freshly verified user to bounce back to /auth before the
      // cache refreshes. SessionManager.isLoggedIn reads currentUser,
      // which is set synchronously when the verify call resolves.
      final isLoggedIn = SessionManager.isLoggedIn;
      final loc = state.matchedLocation;
      final isPublic = _isPublicLocation(loc);
      // Auth-screen routes — the subset of public routes that the
      // signed-in user should be bounced away from (we don't bounce
      // off `/explore/<id>` so an investor can still view a shared
      // link while signed in).
      final isAuthRoute = _publicRoutes.contains(loc);

      // Not signed in + heading to a private route → bounce to /auth.
      if (!isLoggedIn && !isPublic) return RouteNames.auth;
      // Already signed in + on an auth route → bounce to home.
      if (isLoggedIn && isAuthRoute) return RouteNames.home;
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
      // OTP entry — pushed from /login with the email passed as `extra`.
      // Public route (no session yet).
      GoRoute(
        path: RouteNames.otp,
        builder: (context, state) {
          final email = state.extra is String ? state.extra as String : '';
          return OtpScreen(email: email);
        },
      ),
      // Post-login biometric enablement nudge — pushed from the OTP
      // screen after a fresh verifyOTP when user_settings shows
      // biometric_enabled != true. Private route (session required).
      GoRoute(
        path: RouteNames.setupBiometric,
        builder: (context, state) => const SetupBiometricScreen(),
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
      // Legal documents — reachable from setup (pre-auth) and profile
      // footer (post-auth). No bottom nav, no shell.
      GoRoute(
        path: RouteNames.privacy,
        builder: (context, state) => const PrivacyPolicyScreen(),
      ),
      GoRoute(
        path: RouteNames.terms,
        builder: (context, state) => const TermsScreen(),
      ),

      // Full-screen in-app document viewer. Lives outside the shell so
      // the PDF / image canvas isn't squeezed by the bottom-nav bar
      // and so screenshot prevention applies to the entire surface.
      // Reached primarily via Navigator.push from DocumentsScreen, but
      // the path-param route makes deep-links (e.g. from an activity
      // notification "View Document") possible.
      GoRoute(
        path: '${RouteNames.documentViewer}/:id',
        builder: (context, state) => DocumentViewerScreen(
          documentId: state.pathParameters['id'] ?? '',
        ),
      ),

      // First-payout celebration overlay. Full-screen (no bottom nav),
      // pushed by CelebrationTrigger when the investor opens the app
      // with >=1 payout and the seen-flag is unset. Query params:
      //   amount  — INR rupees (double, parsed below)
      //   project — project name (display string)
      //   date    — ISO-8601 payout date
      GoRoute(
        path: '/celebration',
        builder: (context, state) {
          final q = state.uri.queryParameters;
          final amount = double.tryParse(q['amount'] ?? '') ?? 0.0;
          final project = q['project'] ?? '';
          final date =
              DateTime.tryParse(q['date'] ?? '') ?? DateTime.now();
          return CelebrationScreen(
            amount: amount,
            projectName: project,
            date: date,
          );
        },
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
                routes: [
                  // Per-project rich geography + property page. Pushed
                  // from `ProjectActionTiles` (View Area tile).
                  GoRoute(
                    path: 'view-area',
                    builder: (context, state) => ProjectViewAreaScreen(
                      projectId: state.pathParameters['id'] ?? '',
                    ),
                  ),
                  // Per-project photo grid. Pushed from
                  // `ProjectActionTiles` (Photos tile).
                  GoRoute(
                    path: 'photos',
                    builder: (context, state) => ProjectPhotosScreen(
                      projectId: state.pathParameters['id'] ?? '',
                    ),
                  ),
                ],
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
            routes: [
              // Marketplace project detail — pushed from ExploreScreen's
              // ProjectTile.onTap. The path-param is the same id used in
              // `MarketplaceProject` (Supabase project row id).
              GoRoute(
                path: ':projectId',
                builder: (context, state) => ExploreDetailScreen(
                  projectId: state.pathParameters['projectId'] ?? '',
                ),
              ),
            ],
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
