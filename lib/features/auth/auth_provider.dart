import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:arl_app/core/auth/app_lock_provider.dart';
import 'package:arl_app/core/auth/app_lock_service.dart';
import 'package:arl_app/core/auth/secure_session_store.dart';
import 'package:arl_app/core/auth/session_manager.dart';
import 'package:arl_app/core/constants/supabase_constants.dart';
import 'package:arl_app/core/repositories/login_events_repository.dart';
import 'package:arl_app/core/repositories/user_settings_repository.dart';
import 'package:arl_app/core/offline/hive_cache.dart';
import 'package:arl_app/core/supabase/storage_helper.dart';
import 'package:arl_app/core/supabase/supabase_client.dart';
import 'package:arl_app/features/projects/projects_provider.dart';

/// Live auth state — emits whenever Supabase signals signin / signout.
/// In demo mode (no Supabase configured) the stream is empty and we
/// fall back to "logged in" so the UI is reachable.
///
/// NOTE: Supabase's `onAuthStateChange` is a broadcast stream, so any
/// event that fired before this provider subscribed (commonly the
/// INITIAL_SESSION emitted right after `Supabase.initialize`) is lost.
/// We seed the stream with the current session so dependent providers
/// always observe the right state on first build.
final authStateProvider = StreamProvider<AuthState?>((ref) {
  final client = ArlSupabase.client;
  if (client == null) {
    return Stream<AuthState?>.value(null);
  }

  final controller = StreamController<AuthState?>();
  // Seed: current session (or null when signed out) — emitted before
  // any live events so subscribers don't have to wait for the next
  // signin/refresh to learn the user is already authenticated.
  final seedSession = client.auth.currentSession;
  if (seedSession != null) {
    final seed = AuthState(AuthChangeEvent.initialSession, seedSession);
    _syncSentryUser(seed);
    controller.add(seed);
  } else {
    controller.add(null);
  }

  final loginEvents = LoginEventsRepository();
  final secureStore = SecureSessionStore();
  final settingsRepo = UserSettingsRepository();
  final sub = client.auth.onAuthStateChange.listen(
    (event) {
      // Account-boundary hygiene. Runs BEFORE the event is forwarded so
      // dependent providers that rebuild on it never read the previous
      // user's cached rows / signed URLs / project filter.
      if (event.event == AuthChangeEvent.signedIn ||
          event.event == AuthChangeEvent.signedOut) {
        StorageHelper.clear();
        _resetProjectFilter(ref);
      }
      if (event.event == AuthChangeEvent.signedOut) {
        // Hive cache keys are not user-scoped, and repositories fall
        // back to them on network errors — without this wipe, the next
        // person to sign in on this device could see the previous
        // investor's profile, payouts and notifications.
        unawaited(clearUserCaches());
      }
      _syncSentryUser(event);
      controller.add(event);
      // Audit: record a row on real sign-ins (not on every token refresh
      // or the seeded initialSession event — that fires on cold start
      // even when the user hasn't actually re-authenticated).
      if (event.event == AuthChangeEvent.signedIn) {
        unawaited(loginEvents.recordLogin());
      }
      // Persist refresh token for biometric reuse on signedIn /
      // tokenRefreshed. Gated by user_settings.biometric_enabled so
      // disabling biometric on one device tears the cache down on the
      // next refresh elsewhere too.
      if (event.event == AuthChangeEvent.signedIn ||
          event.event == AuthChangeEvent.tokenRefreshed) {
        final session = event.session;
        final email = session?.user.email;
        final refresh = session?.refreshToken;
        if (email != null && refresh != null) {
          unawaited(() async {
            try {
              final row = await settingsRepo.mySettings();
              final enabled = row?['biometric_enabled'] == true;
              if (enabled) {
                await secureStore.saveSession(
                  email: email,
                  refreshToken: refresh,
                );
                await secureStore.setBiometricEnabled(true);
              } else {
                await secureStore.clearBiometric();
              }
            } catch (_) {
              // Cache-only path — never let it surface as a user-visible
              // error.
            }
          }());
        }
      }
      if (event.event == AuthChangeEvent.signedOut) {
        unawaited(secureStore.clearBiometric());
        // Wipe the per-device app-lock state too — a different user
        // signing in on this device should not inherit the previous
        // user's PIN hash or biometric opt-in flag.
        unawaited(AppLockService().clearAll().then((_) {
          // Invalidate the settings cache so SecurityScreen / lock
          // gate re-read the now-empty state instead of seeing stale
          // pre-signout values.
          ref.invalidate(appLockSettingsProvider);
        }));
      }
    },
    onError: controller.addError,
  );
  ref.onDispose(() {
    sub.cancel();
    controller.close();
  });
  return controller.stream;
});

void _resetProjectFilter(Ref ref) {
  try {
    ref.read(selectedProjectIdProvider.notifier).state = null;
  } catch (_) {
    // Provider not yet mounted — nothing to reset.
  }
}

void _syncSentryUser(AuthState event) {
  final user = event.session?.user;
  if (event.event == AuthChangeEvent.signedOut) {
    Sentry.configureScope((scope) => scope.setUser(null));
  } else if (user != null &&
      (event.event == AuthChangeEvent.signedIn ||
          event.event == AuthChangeEvent.initialSession)) {
    Sentry.configureScope((scope) => scope.setUser(SentryUser(id: user.id)));
  }
}

final isLoggedInProvider = Provider<bool>((ref) {
  // Watch auth state to rebuild on changes.
  ref.watch(authStateProvider);
  if (SupabaseConstants.isDemoMode) return true;
  if (SupabaseConstants.devBypassAuth) return true;
  return SessionManager.isLoggedIn;
});
