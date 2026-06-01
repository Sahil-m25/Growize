import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:arl_app/core/constants/supabase_constants.dart';
import 'package:arl_app/core/supabase/supabase_client.dart';

/// Thin wrapper around Supabase auth. Pure static surface so screens
/// don't need to take a dependency on Supabase types directly.
///
/// Auth model (locked 2026-05-21): email OTP only. There is no
/// password flow — every sign-in goes through [signInWithOtp] (which
/// proxies the `request-auth-email` Edge Function so unknown emails
/// are silently dropped server-side) followed by [verifyEmailOtp].
class SessionManager {
  /// True only when Supabase is configured AND there's a current session.
  static bool get isLoggedIn {
    final c = ArlSupabase.client;
    if (c == null) {
      // Demo mode — pretend the user is logged in so screens render.
      return true;
    }
    return c.auth.currentUser != null;
  }

  /// Stream of auth state changes. Empty stream in demo mode.
  static Stream<AuthState> get authStateChanges {
    final c = ArlSupabase.client;
    if (c == null) return const Stream.empty();
    return c.auth.onAuthStateChange;
  }

  static String? get currentUserId => ArlSupabase.currentUserId;

  // ── auth methods ───────────────────────────────────────────────────────

  /// Request an email-delivered OTP. Routes through the
  /// `request-auth-email` Edge Function so we only send to addresses
  /// that actually map to an investor (invite-only enumeration
  /// protection). The function always returns `{ok:true}` — never
  /// throws on "unknown email". Throws on transport / 4xx / 5xx so
  /// the UI can surface a generic "couldn't reach server" message.
  static Future<void> signInWithOtp({required String email}) async {
    await _requestAuthEmail(email: email, mode: 'magic_link');
  }

  /// Internal: POSTs to the auth-gate Edge Function. Throws on
  /// transport / non-2xx so the UI can show a generic "couldn't
  /// reach server" message — success vs "email unknown" is
  /// indistinguishable by design.
  static Future<void> _requestAuthEmail({
    required String email,
    required String mode,
  }) async {
    final client = ArlSupabase.requireClient();
    final secret = SupabaseConstants.authGateSecret;
    if (secret.isEmpty) {
      throw const AuthException(
        'Auth gate not configured. Contact support.',
      );
    }
    final res = await client.functions.invoke(
      SupabaseConstants.fnRequestAuthEmail,
      body: {'email': email, 'mode': mode},
      headers: {'x-arl-cron-secret': secret},
    );
    final status = res.status;
    if (status < 200 || status >= 300) {
      throw AuthException('Auth service unavailable (HTTP $status).');
    }
  }

  /// Verify the email OTP code the user typed in.
  static Future<void> verifyEmailOtp({
    required String email,
    required String token,
  }) async {
    final client = ArlSupabase.requireClient();
    await client.auth.verifyOTP(
      email: email,
      token: token,
      type: OtpType.email,
    );
  }

  static Future<void> signOut() async {
    final c = ArlSupabase.client;
    if (c == null) return;
    await c.auth.signOut();
  }

  /// Recover a session from a previously cached refresh token. Used by
  /// the biometric login flow — the user has already proven identity
  /// via fingerprint/face, so we redeem the cached token rather than
  /// asking for a code.
  static Future<void> signInWithRefreshToken(String refreshToken) async {
    final client = ArlSupabase.requireClient();
    await client.auth.setSession(refreshToken);
  }

  // ── legacy zoho stubs — kept so old code compiles, will be removed
  //    once the auth path is finalised. ─────────────────────────────────
  static void saveZohoTokens({
    required String accessToken,
    required String refreshToken,
  }) {}
  static String? get zohoAccessToken => null;
  static String? get zohoRefreshToken => null;
}
