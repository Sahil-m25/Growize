import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:arl_app/core/constants/supabase_constants.dart';

/// Initialises Supabase. Safe to call multiple times — Supabase.initialize
/// is idempotent. If running in demo mode (no env vars), this is a no-op.
class ArlSupabase {
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    if (!SupabaseConstants.isConfigured) {
      // Demo / unconfigured — providers fall back to mocks.
      _initialized = true;
      return;
    }
    await Supabase.initialize(
      url: SupabaseConstants.url,
      anonKey: SupabaseConstants.anonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
      // Realtime stays default — we only need it for notifications later.
    );
    _initialized = true;
  }

  /// Throws if not initialized. Callers should prefer [client] which handles
  /// demo-mode by returning null.
  static SupabaseClient get _raw => Supabase.instance.client;

  /// Returns null in demo mode. All repositories must check for null before
  /// querying — null means "fall back to mock data".
  static SupabaseClient? get client {
    if (!_initialized || !SupabaseConstants.isConfigured) return null;
    return _raw;
  }

  /// Convenience for code that genuinely cannot proceed without a client
  /// (e.g. login submit). Throws StateError if called in demo mode.
  static SupabaseClient requireClient() {
    final c = client;
    if (c == null) {
      throw StateError(
        'Supabase is not configured. Set SUPABASE_URL + SUPABASE_ANON_KEY in .env.',
      );
    }
    return c;
  }

  static String? get currentUserId => client?.auth.currentUser?.id;

  static bool get isSignedIn => client?.auth.currentUser != null;
}
