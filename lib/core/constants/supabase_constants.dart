import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Reads Supabase config from `.env` (loaded in main.dart before runApp).
/// Keep this file the only place we read SUPABASE_* env vars.
abstract final class SupabaseConstants {
  static String get url =>
      dotenv.maybeGet('SUPABASE_URL', fallback: '') ?? '';

  static String get anonKey =>
      dotenv.maybeGet('SUPABASE_ANON_KEY', fallback: '') ?? '';

  /// True only when both URL + anon key are present.
  /// When false, the app stays in demo mode regardless of ARL_APP_MODE.
  static bool get isConfigured =>
      url.isNotEmpty && anonKey.isNotEmpty;

  /// 'live' (default) or 'demo'. Demo skips all network calls.
  static String get mode =>
      (dotenv.maybeGet('ARL_APP_MODE', fallback: 'live') ?? 'live').toLowerCase();

  static bool get isDemoMode => mode == 'demo';

  /// B.T2: Dev-only flag gated behind kReleaseMode.
  /// In release mode, devBypassAuth is always false (cannot be overridden).
  /// In debug, when ARL_DEV_BYPASS=true in .env, the router treats
  /// the user as signed-in even with no Supabase session. Useful for
  /// previewing screens before the auth flow is finished. NEVER ship true.
  static bool get devBypassAuth {
    if (kReleaseMode) return false;
    return (dotenv.maybeGet('ARL_DEV_BYPASS', fallback: 'false') ?? 'false')
            .toLowerCase() ==
        'true';
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
