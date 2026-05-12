import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:arl_app/core/offline/hive_cache.dart';

/// Tracks app-wide network sync state.
///
/// - [lastSyncAtProvider] holds the most recent successful round-trip to
///   Supabase. Persisted to Hive so a fresh launch surfaces the last
///   timestamp instantly.
/// - [fetchInFlightProvider] counts in-flight tracked fetches. >0 means
///   the UI should show "Live" instead of "X ago".
/// - Use [trackedFetch] to wrap any Supabase call so the timestamp + live
///   indicator stay accurate without manual bookkeeping at each site.
const String _syncBox = HiveBoxes.home;
const String _syncKey = 'last_sync_at_iso';

/// Restored from Hive on first read; updated on every successful fetch.
final lastSyncAtProvider = StateProvider<DateTime?>((ref) {
  try {
    final raw = hiveBox(_syncBox).get(_syncKey) as String?;
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  } catch (_) {
    return null;
  }
});

/// Active fetch counter. 0 = idle. >0 = at least one fetch in-flight.
final fetchInFlightProvider = StateProvider<int>((ref) => 0);

/// Convenience flag for the UI: "Live" when true, "X ago" otherwise.
final isLiveProvider = Provider<bool>((ref) {
  return ref.watch(fetchInFlightProvider) > 0;
});

/// Hard ceiling for any tracked fetch. Web builds can stall forever on
/// CORS preflight failures or stuck WebSocket reconnects, so we never let
/// a single request block the UI past this window. Tuned so a healthy
/// Supabase round-trip (typically 200–800 ms) is comfortably under it.
const Duration kTrackedFetchTimeout = Duration(seconds: 8);

/// Wrap a Supabase call so it updates [lastSyncAtProvider] +
/// [fetchInFlightProvider] for the duration. Times out after
/// [kTrackedFetchTimeout] so a hung request can't keep the UI in
/// skeleton state forever. Errors / timeouts are rethrown — the caller
/// decides cache fallback semantics.
///
/// Yields one microtask before any `ref.read` mutation so we're not
/// modifying [fetchInFlightProvider] / [lastSyncAtProvider] during the
/// calling provider's build phase. Riverpod 2.x asserts on that pattern
/// (and the assertion was the root cause of every repo call returning
/// `null` → demo fallthrough on web).
Future<T> trackedFetch<T>(Ref ref, Future<T> Function() body) async {
  // Step out of the caller's synchronous build phase before touching
  // any other provider's state.
  await Future<void>.value();

  final inFlight = ref.read(fetchInFlightProvider.notifier);
  inFlight.update((n) => n + 1);
  final stopwatch = Stopwatch()..start();
  try {
    final result = await body().timeout(kTrackedFetchTimeout);
    final now = DateTime.now();
    ref.read(lastSyncAtProvider.notifier).state = now;
    try {
      await hiveBox(_syncBox).put(_syncKey, now.toIso8601String());
    } catch (_) {
      // Hive write failure shouldn't break the request.
    }
    if (kDebugMode) {
      debugPrint('[trackedFetch] OK in ${stopwatch.elapsedMilliseconds}ms');
    }
    return result;
  } catch (e) {
    if (kDebugMode) {
      debugPrint(
          '[trackedFetch] FAIL in ${stopwatch.elapsedMilliseconds}ms: $e');
    }
    rethrow;
  } finally {
    inFlight.update((n) => (n - 1).clamp(0, 1 << 30));
  }
}

/// Format a "Updated …" label. Live > 0s ago > 1m ago > Xm/Xh/Xd ago.
/// Returns 'Updated …' when timestamp null and not live (e.g. cold start
/// before first fetch).
String formatSyncLabel({required DateTime? syncedAt, required bool isLive}) {
  if (isLive) return 'Live';
  if (syncedAt == null) return 'Updated …';
  final diff = DateTime.now().difference(syncedAt);
  if (diff.inSeconds < 30) return 'Updated just now';
  if (diff.inMinutes < 1) return 'Updated ${diff.inSeconds}s ago';
  if (diff.inMinutes < 60) return 'Updated ${diff.inMinutes}m ago';
  if (diff.inHours < 24) return 'Updated ${diff.inHours}h ago';
  return 'Updated ${diff.inDays}d ago';
}
