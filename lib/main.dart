import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/observability/sentry_config.dart';
import 'core/offline/hive_cache.dart';
import 'core/supabase/supabase_client.dart';
import 'core/supabase/storage_helper.dart';
import 'core/navigation/router.dart';
import 'core/theme/arl_theme.dart';
import 'core/constants/supabase_constants.dart';
import 'core/widgets/demo_mode_banner.dart';
import 'features/gating/gating_provider.dart';
import 'features/gating/force_update_screen.dart';
import 'features/gating/maintenance_screen.dart';
import 'core/providers/repositories.dart';
import 'features/auth/auth_provider.dart';
import 'features/activity/activity_provider.dart';
import 'features/financials/financials_provider.dart';
import 'features/projects/projects_provider.dart';
import 'features/documents/documents_provider.dart';
import 'features/gallery/gallery_provider.dart';

late ProviderContainer _container;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // B.T1: Hard-fail dotenv in release mode.
  // In debug, tolerate missing .env (design previews).
  // In release, require it and assert config is valid.
  try {
    await dotenv.load(fileName: '.env');
  } catch (e) {
    if (kReleaseMode) {
      throw StateError('Failed to load .env in release mode: $e');
    }
  }

  // B.T1: Assert Supabase is configured in release mode.
  if (kReleaseMode) {
    if (!SupabaseConstants.isConfigured) {
      throw StateError('Supabase not configured in release mode');
    }
    if (SupabaseConstants.devBypassAuth) {
      throw StateError('devBypassAuth cannot be true in release mode');
    }
  }

  // Hive — local cache. Safe even when offline.
  await initHive();

  // Supabase — no-op when env not configured.
  await ArlSupabase.init();

  // Sentry crash reporting. Configuration is read at COMPILE TIME via
  // `--dart-define-from-file=.env.production`. Empty DSN skips init,
  // so dev builds without the flag boot cleanly. Privacy posture lives
  // alongside the beforeSend scrubber in
  // `core/observability/sentry_config.dart`.
  const sentryDsn = String.fromEnvironment('SENTRY_DSN');
  const sentryEnvironment =
      String.fromEnvironment('SENTRY_ENVIRONMENT', defaultValue: 'unknown');
  const sentryRelease =
      String.fromEnvironment('SENTRY_RELEASE', defaultValue: 'unset');

  Future<void> appRunner() async {
    runApp(
      ProviderScope(
        observers: [_ProviderObserver()],
        child: const ArlApp(),
      ),
    );
  }

  if (sentryDsn.isNotEmpty) {
    await SentryFlutter.init(
      (options) {
        options.dsn = sentryDsn;
        options.environment = sentryEnvironment;
        options.release = sentryRelease;
        // Performance monitoring off for v1 — crash reporting only.
        options.tracesSampleRate = 0.0;
        // Privacy hardening — see sentry_config.dart for the full
        // rationale. Do NOT flip any of these without a privacy review.
        options.sendDefaultPii = false;
        options.attachScreenshot = false;
        // Sentry 9.x marks attachViewHierarchy experimental, but we want
        // it pinned to false explicitly so a future default flip can't
        // silently start sending the widget tree.
        // ignore: experimental_member_use
        options.attachViewHierarchy = false;
        options.maxBreadcrumbs = 50;
        options.diagnosticLevel = SentryLevel.warning;
        options.beforeSend = scrubPii;
      },
      appRunner: appRunner,
    );
  } else {
    await appRunner();
  }
}

/// D.T3: Custom observer to capture the ProviderContainer for auth-state-driven
/// provider invalidation.
class _ProviderObserver extends ProviderObserver {
  @override
  void didUpdateProvider(ProviderBase<dynamic> provider, dynamic previousValue,
      dynamic newValue, ProviderContainer container) {
    // Capture container when isLoggedInProvider updates.
    if (provider == isLoggedInProvider) {
      _container = container;

      // B.T5 + D.T3: Invalidate user-scoped providers on auth state change.
      // This runs every time auth state changes (sign-in, sign-out, etc.).
      ArlSupabase.client?.auth.onAuthStateChange.listen((event) {
        if (event.event == AuthChangeEvent.signedIn ||
            event.event == AuthChangeEvent.signedOut ||
            event.event == AuthChangeEvent.userUpdated ||
            event.event == AuthChangeEvent.initialSession ||
            event.event == AuthChangeEvent.tokenRefreshed) {
          // Invalidate all user-scoped caches.
          _container.invalidate(currentInvestorProvider);
          _container.invalidate(payoutsProvider);
          _container.invalidate(projectsProvider);
          _container.invalidate(notificationsProvider);
          _container.invalidate(documentsProvider);
          _container.invalidate(galleryProvider);
          StorageHelper.clear();

          // E.T1: Configure Sentry user scope on auth state change.
          if (event.event == AuthChangeEvent.signedIn &&
              event.session?.user != null) {
            Sentry.configureScope((scope) {
              scope.setUser(SentryUser(id: event.session!.user.id));
            });
          } else if (event.event == AuthChangeEvent.signedOut) {
            Sentry.configureScope((scope) {
              scope.setUser(null);
            });
          }
        }
      });
    }
  }
}

class ArlApp extends ConsumerWidget {
  const ArlApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // B.T7: Check app_config gates before showing the main app.
    final gateAsync = ref.watch(gateStatusProvider);

    return gateAsync.when(
      data: (gateStatus) {
        if (gateStatus.state == GateState.forceUpdate) {
          return MaterialApp(
            title: 'Growize',
            theme: arlTheme,
            debugShowCheckedModeBanner: false,
            home: ForceUpdateScreen(
              currentVersion: gateStatus.currentVersion,
              minimumVersion: gateStatus.minimumVersion ?? '1.0.0',
            ),
          );
        }

        if (gateStatus.state == GateState.maintenance) {
          return MaterialApp(
            title: 'Growize',
            theme: arlTheme,
            debugShowCheckedModeBanner: false,
            home: MaintenanceScreen(
              onRetry: () async {
                // Invalidate the gate provider to re-check.
                ref.invalidate(gateStatusProvider);
              },
            ),
          );
        }

        // Normal app flow.
        final router = ref.watch(routerProvider);
        return MaterialApp.router(
          title: 'Growize',
          theme: arlTheme,
          routerConfig: router,
          debugShowCheckedModeBanner: false,
          builder: (context, child) {
            return Column(
              children: [
                const AppDemoModeBanner(),
                Expanded(child: child ?? const SizedBox.shrink()),
              ],
            );
          },
        );
      },
      loading: () {
        return MaterialApp(
          title: 'Growize',
          theme: arlTheme,
          debugShowCheckedModeBanner: false,
          home: const Scaffold(
            backgroundColor: Color(0xFFFAFAF7),
            body: Center(
              child: CircularProgressIndicator(),
            ),
          ),
        );
      },
      error: (_, __) {
        // If gating check fails, allow app to proceed.
        final router = ref.watch(routerProvider);
        return MaterialApp.router(
          title: 'Growize',
          theme: arlTheme,
          routerConfig: router,
          debugShowCheckedModeBanner: false,
          builder: (context, child) {
            return Column(
              children: [
                const AppDemoModeBanner(),
                Expanded(child: child ?? const SizedBox.shrink()),
              ],
            );
          },
        );
      },
    );
  }
}
