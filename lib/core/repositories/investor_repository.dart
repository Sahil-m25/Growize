import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:arl_app/core/offline/hive_cache.dart';
import 'package:arl_app/core/offline/resilient_cache.dart';
import 'package:arl_app/core/supabase/supabase_client.dart';

/// Reads the currently signed-in investor's row.
/// One investor per auth.users row, so we look up by id = auth.uid().
///
/// Resilience: caches the last successful row to Hive and returns it on
/// connectivity failures so the profile / dashboard never blanks out.
/// PostgREST / RLS errors (real backend problems) are surfaced rather
/// than masked, so the UI can show "could not load" instead of silently
/// falling back to demo data.
///
/// We rely on RLS (`id = auth.uid()`) for filtering rather than echoing
/// `currentUserId` back as a `.eq` clause — that way the query is
/// driven by the JWT in the request, not by a Dart-side getter that
/// can race with Supabase session restoration.
class InvestorRepository {
  static const _box = HiveBoxes.auth;
  static const _kInvestor = 'current_investor';

  /// Total time we'll poll for `currentSession` before falling back to
  /// the cache. Covers the small window between `signInWithPassword`
  /// resolving on web and the JWT being attached to outgoing requests,
  /// and the broader window where Supabase restores a stored session
  /// during app boot.
  static const _sessionWait = Duration(seconds: 5);
  static const _pollInterval = Duration(milliseconds: 100);

  Future<Map<String, dynamic>?> currentInvestor() async {
    final client = ArlSupabase.client;
    if (client == null) return _readCache();

    // Poll for session — broadcast stream subscribers can miss the
    // INITIAL_SESSION / SIGNED_IN event if the event fired before the
    // listener was attached, so we don't rely on the stream alone.
    final deadline = DateTime.now().add(_sessionWait);
    while (client.auth.currentSession == null &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(_pollInterval);
    }
    if (client.auth.currentSession == null) return _readCache();

    try {
      // Rely on RLS to filter to the row whose id = auth.uid().
      final row =
          await client.from('investors').select().limit(1).maybeSingle();
      if (row == null) return null;
      final map = Map<String, dynamic>.from(row);
      await ResilientCache.putMap(_box, _kInvestor, map);
      return map;
    } on PostgrestException {
      // Real backend / RLS / schema error — surface it.
      rethrow;
    } on SocketException {
      return _readCache();
    } on TimeoutException {
      return _readCache();
    }
  }

  Map<String, dynamic>? _readCache() {
    return ResilientCache.getMap(_box, _kInvestor);
  }
}
