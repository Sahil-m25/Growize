import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/auth/app_lock_provider.dart';
import 'core/auth/web_session_native.dart'
    if (dart.library.js_interop) 'core/auth/web_session_web.dart';
import 'core/theme/arl_colors.dart';
import 'core/observability/sentry_config.dart';
import 'core/offline/hive_cache.dart';
import 'core/supabase/supabase_client.dart';
import 'core/supabase/storage_helper.dart';
import 'core/navigation/router.dart';
import 'core/theme/arl_theme.dart';
import 'core/constants/supabase_constants.dart';
import 'core/widgets/demo_mode_banner.dart';
import 'core/widgets/app_error_view.dart';
import 'features/auth/lock_screen.dart';
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

/// Web-friendly scroll behaviour — enables mouse drag and trackpad-pan
/// gestures alongside touch. Without this, Flutter web's default
/// ScrollBehavior only recognises touch input, so SingleChildScrollView /
/// GridView / ListView feel unresponsive on desktop (only the scrollbar
/// works, never click-and-drag on the body itself).
class _AppScrollBehavior extends MaterialScrollBehavior {
  const _AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
      };
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Global safety net: if any widget throws during build, show a calm
  // branded card instead of Flutter's red/grey error box. Sentry still
  // captures the underlying exception via FlutterError.onError.
  ErrorWidget.builder =
      (FlutterErrorDetails details) => AppErrorView.forFlutterError(details);

  // B.T1: Load dotenv on native only.
  // On web, all config is baked in at compile time via
  // --dart-define-from-file, so there is no .env asset to load.
  // Netlify also blocks dotfiles (HTTP 404), which would crash the app.
  if (!kIsWeb) {
    try {
      await dotenv.load(fileName: '.env');
    } catch (e) {
      if (kReleaseMode) {
        throw StateError('Failed to load .env in release mode: $e');
      }
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

  // SentryFlutter.init has known issues on some Flutter web builds.
  // Use it on native only; on web run the app directly.
  if (sentryDsn.isNotEmpty && !kIsWeb) {
    await SentryFlutter.init(
      (options) {
        options.dsn = sentryDsn;
        options.environment = sentryEnvironment;
        options.release = sentryRelease;
        options.tracesSampleRate = 0.0;
        options.sendDefaultPii = false;
        options.attachScreenshot = false;
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

class ArlApp extends ConsumerStatefulWidget {
  const ArlApp({super.key});

  @override
  ConsumerState<ArlApp> createState() => _ArlAppState();
}

class _ArlAppState extends ConsumerState<ArlApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Kick off the lock-settings load. The provider's side-effect flips
    // `appLockedProvider` off when no gate is configured, so we don't
    // strand users without any reason to be locked.
    Future<void>.microtask(() {
      ref.read(lockBootProvider);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && kIsWeb) {
      // Web / PWA: sign out if the user has been idle for too long.
      if (isWebSessionExpired()) {
        ArlSupabase.client?.auth.signOut();
        clearWebSession();
      } else {
        refreshWebSession();
      }
      return;
    }
    // App lock is not supported on web.
    if (kIsWeb) return;
    final controller = ref.read(appLockControllerProvider);
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        // Note the backgrounding instant. We don't re-lock immediately —
        // brief OS overlays (notification shade, app switcher) would
        // otherwise nag the user on every flip back. The grace window in
        // [AppLockService.resumeGrace] decides whether to actually lock.
        controller.noteBackgrounded();
        break;
      case AppLifecycleState.resumed:
        // Read current settings synchronously where possible — if the
        // FutureProvider has resolved we already have the answer; if
        // not, default to "lock" out of caution.
        final settings = ref.read(appLockSettingsProvider).asData?.value;
        if (settings != null && settings.lockEnabled) {
          if (controller.shouldChallengeOnResume()) {
            controller.lock();
          }
        }
        break;
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
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
          scrollBehavior: const _AppScrollBehavior(),
          builder: (context, child) {
            Widget body = Column(
              children: [
                const AppDemoModeBanner(),
                Expanded(
                  child: _LockGate(
                    child: child ?? const SizedBox.shrink(),
                  ),
                ),
              ],
            );
            // Web/PWA: wrap in a Listener so every tap refreshes the
            // idle timer. No-op on native (refreshWebSession is a stub).
            if (kIsWeb) {
              body = Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (_) => refreshWebSession(),
                child: body,
              );
            }
            return body;
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
          scrollBehavior: const _AppScrollBehavior(),
          builder: (context, child) {
            return Column(
              children: [
                const AppDemoModeBanner(),
                Expanded(
                  child: _LockGate(
                    child: child ?? const SizedBox.shrink(),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Renders the lock screen on top of the router when (a) the user is
/// signed in, (b) at least one lock option is configured, and (c) the
/// runtime "locked" flag is on. Listens to the boot provider so the
/// initial settings load triggers a rebuild as soon as it resolves.
class _LockGate extends ConsumerWidget {
  final Widget child;
  const _LockGate({required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Trigger initial settings load. The boot provider flips
    // `appLockedProvider` off when no lock is configured.
    ref.watch(lockBootProvider);

    final isLoggedIn = ref.watch(isLoggedInProvider);
    final settingsAsync = ref.watch(appLockSettingsProvider);
    final locked = ref.watch(appLockedProvider);
    final settings = settingsAsync.asData?.value;

    // Web has no biometric / PIN support — lock gate is a no-op.
    if (kIsWeb) return child;
    // Signed-out users never see the lock — sign-in screens own that flow.
    if (!isLoggedIn) return child;
    // Explicitly unlocked? Pass through.
    if (!locked) return child;
    // Settings haven't resolved yet — show a neutral splash instead of
    // leaking authenticated content while we read secure storage. Wrap
    // in SizedBox.expand so the splash claims the full pane even when
    // the parent gives us loose constraints.
    if (settings == null) {
      return const SizedBox.expand(
        child: ColoredBox(
          color: ArlColors.primary,
          child: Center(
            child: CircularProgressIndicator(color: ArlColors.gold),
          ),
        ),
      );
    }
    // No lock configured — pass through.
    if (!settings.lockEnabled) return child;

    // Keep the underlying app alive in the tree (so its state survives)
    // but render the LockScreen above it.
    //
    // IMPORTANT: `Stack(fit: StackFit.expand)` is load-bearing. A bare
    // Stack sizes itself to fit its non-positioned children — and the
    // only non-positioned child here is `Offstage(offstage: true, ...)`,
    // which collapses to 0x0. The previous implementation produced a
    // 0x0 Stack and a `Positioned.fill` that filled nothing, leaving a
    // BLANK SCREEN. `StackFit.expand` makes the Stack grow to its parent
    // constraints (Expanded), so the LockScreen has somewhere to draw.
    return Stack(
      fit: StackFit.expand,
      children: [
        // The router content is offstage during lock so its inputs
        // can't be touched, but the widget tree is preserved.
        Offstage(offstage: true, child: child),
        // LockScreen is a full Scaffold — no need to wrap it in Material
        // (that produced a redundant ink-well overlay). Painting the
        // brand background here is still useful as a defensive backstop
        // in case LockScreen ever returns SizedBox.shrink during a
        // transient state.
        const Positioned.fill(
          child: ColoredBox(
            color: ArlColors.primary,
            child: LockScreen(),
          ),
        ),
      ],
    );
  }
}
