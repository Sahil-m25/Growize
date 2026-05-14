import 'package:flutter/foundation.dart';

/// Reads Supabase config via `--dart-define` / `--dart-define-from-file`.
///
/// Build / run:
///   flutter run --dart-define-from-file=.env.production
///   flutter build web --release --dart-define-from-file=.env.production
///
/// Debug-only fallbacks (gated by [kDebugMode]) keep `flutter run` working
/// during design previews even when no env file is supplied. Release builds
/// see an empty config unless dart-defines are provided, which causes
/// [isConfigured] to return false and the app to refuse to start (asserted
/// from main.dart).
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

  static String get url => _urlDefine;
  static String get anonKey => _anonKeyDefine;

  /// True only when both URL + anon key are present.
  /// When false, the app stays in demo mode regardless of ARL_APP_MODE.
  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;

  /// 'live' (default) or 'demo'. Demo skips all network calls.
  static String get mode => _modeDefine.toLowerCase();

  static bool get isDemoMode => mode == 'demo';

  /// Dev-only flag gated behind [kReleaseMode]. In release, always false.
  /// In debug, when ARL_DEV_BYPASS=true is passed via dart-define, the router
  /// treats the user as signed-in even with no Supabase session. Useful for
  /// previewing screens before the auth flow is finished. NEVER ship true.
  static bool get devBypassAuth {
    if (kReleaseMode) return false;
    return _devBypassDefine.toLowerCase() == 'true';
  }

  /// Storage bucket names — must match what's created via the Supabase CLI.
  static const String documentsBucket = 'arl-documents';
  static const String galleryBucket = 'arl-gallery';

  /// Edge Function endpoints (relative paths — full URL composed at call site).
  static const String fnOnboardInvestor = 'onboard-investor';
  static const String fnCreateTicket = 'create-ticket';
  static const String fnReplyTicket = 'reply-ticket';
  static const String fnBankChangeRequest = 'bank-change-request';
}
