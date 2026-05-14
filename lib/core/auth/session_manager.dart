import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:arl_app/core/supabase/supabase_client.dart';

/// Thin wrapper around Supabase auth. Pure static surface so screens
/// don't need to take a dependency on Supabase types directly.
///
/// Two stub auth methods are kept (phone OTP via login_screen and a
/// 3-step setup) — neither is wired to Supabase yet. When you choose
/// between Supabase email-password (Decision #1 in backend doc) or
/// magic link / OTP, fill in [signInWithEmailPassword] /
/// [signInWithOtp] / [verifyOtp] in this file. The rest of the app
/// reads through [authStateChanges] / [isLoggedIn] and won't change.
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

  // ── auth methods (stubs — pick one, then wire here) ────────────────────

  /// Supabase email + password (matches Decision #1 in backend doc).
  /// Throws AuthException on failure.
  static Future<void> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    final client = ArlSupabase.requireClient();
    await client.auth.signInWithPassword(email: email, password: password);
  }

  /// Magic link / OTP request. Sends an email, user gets a code.
  static Future<void> signInWithOtp({required String email}) async {
    final client = ArlSupabase.requireClient();
    await client.auth.signInWithOtp(email: email);
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
  /// asking for a password.
  static Future<void> signInWithRefreshToken(String refreshToken) async {
    final client = ArlSupabase.requireClient();
    await client.auth.setSession(refreshToken);
  }

  /// B.T4: Request a password reset. Sends an email with a recovery link.
  /// Throws AuthException on failure.
  static Future<void> requestPasswordReset(String email) async {
    final client = ArlSupabase.requireClient();
    await client.auth.resetPasswordForEmail(email);
  }

  /// B.T4: Update the user's password (used after recovery link).
  /// Throws AuthException on failure.
  static Future<void> updatePassword(String newPassword) async {
    final client = ArlSupabase.requireClient();
    await client.auth.updateUser(
      UserAttributes(password: newPassword),
    );
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
