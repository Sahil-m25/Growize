import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Reads Supabase config from `--dart-define` (compile-time) with a
/// runtime fallback to `flutter_dotenv` so the app boots either way:
///
///   flutter build web   --release  (uses bundled `.env` via dotenv)
///   flutter build apk   --release  (uses bundled `.env` via dotenv)
///   flutter build *     --dart-define-from-file=.env.production
///                                  (uses compile-time defines — preferred
///                                   for CI / hardened builds)
///
/// If both sources are empty in release mode, main.dart asserts and the
/// app refuses to start (see the kReleaseMode block in lib/main.dart).
abstract final class SupabaseConstants {
  /// Supabase project URL. Provide via `SUPABASE_URL=...` in your env file.
  static const String _urlDefine =
      String.fromEnvironment('SUPABASE_URL', defaultValue: '');

  /// Supabase anon (publishable) key.
  static const String _anonKeyDefine =
      String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

  /// Optional mode override. `live` (default) or `demo`. In `demo` mode the
  /// app skips all network calls and renders mock data.
  static const String _modeDefine =
      String.fromEnvironment('ARL_APP_MODE', defaultValue: 'live');

  /// Dev-only flag. Forced to `false` in release regardless of dart-define.
  static const String _devBypassDefine =
      String.fromEnvironment('ARL_DEV_BYPASS', defaultValue: 'false');

  /// Returns the compile-time `String.fromEnvironment` value if present;
  /// otherwise falls back to `flutter_dotenv` (loaded in main.dart from
  /// the bundled `.env` asset); otherwise returns the explicit fallback.
  static String _envOr(String defineValue, String key, [String fallback = '']) {
    if (defineValue.isNotEmpty) return defineValue;
    try {
      final v = dotenv.maybeGet(key);
      if (v != null && v.isNotEmpty) return v;
    } catch (_) {
      // dotenv not initialised (e.g. main.dart's load failed in debug);
      // fall through to the explicit fallback.
    }
    return fallback;
  }

  static String get url => _envOr(_urlDefine, 'SUPABASE_URL');
  static String get anonKey => _envOr(_anonKeyDefine, 'SUPABASE_ANON_KEY');

  /// True only when both URL + anon key are present.
  /// When false, the app stays in demo mode regardless of ARL_APP_MODE.
  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;

  /// 'live' (default) or 'demo'. Demo skips all network calls.
  static String get mode =>
      _envOr(_modeDefine, 'ARL_APP_MODE', 'live').toLowerCase();

  static bool get isDemoMode => mode == 'demo';

  /// Dev-only flag gated behind [kReleaseMode]. In release, always false.
  /// In debug, when ARL_DEV_BYPASS=true is passed via dart-define OR
  /// present in `.env`, the router treats the user as signed-in even with
  /// no Supabase session. Useful for previewing screens before the auth
  /// flow is finished. NEVER ship true.
  static bool get devBypassAuth {
    if (kReleaseMode) return false;
    final v = _envOr(_devBypassDefine, 'ARL_DEV_BYPASS', 'false');
    return v.toLowerCase() == 'true';
  }

  /// Storage bucket names — must match what's created via the Supabase CLI.
  static const String documentsBucket = 'arl-documents';
  static const String galleryBucket = 'arl-gallery';

  /// Edge Function endpoints (relative paths — full URL composed at call site).
  static const String fnOnboardInvestor = 'onboard-investor';
  static const String fnCreateTicket = 'create-ticket';
  static const String fnReplyTicket = 'reply-ticket';
  static const String fnBankChangeRequest = 'bank-change-request';
  static const String fnRequestAuthEmail = 'request-auth-email';
  static const String fnLatestAppVersion = 'latest-app-version';

  /// Shared secret sent in the `x-arl-cron-secret` header when calling
  /// the `request-auth-email` Edge Function. Separate from CRON_SECRET
  /// so the value baked into the Flutter binary can be rotated without
  /// touching DB-trigger-fired functions.
  static const String _authGateSecretDefine =
      String.fromEnvironment('ARL_AUTH_GATE_SECRET', defaultValue: '');
  static String get authGateSecret =>
      _envOr(_authGateSecretDefine, 'ARL_AUTH_GATE_SECRET');
}
