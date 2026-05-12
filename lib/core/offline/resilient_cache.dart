import 'package:arl_app/core/offline/hive_cache.dart';

/// Tiny generic JSON cache helper sitting on top of Hive.
///
/// Each repository keeps its own (boxName, key) tuple. The shape we store
/// is whatever the caller already serialises — typically a `List<Map>` or
/// a single `Map<String, dynamic>`.
///
/// On first launch (cache miss) the read methods return null, letting the
/// caller decide whether to surface a skeleton, an empty state, or a
/// retryable placeholder. Crucially we NEVER throw — the goal is to keep
/// the UI from going blank when Supabase blips.
class ResilientCache {
  ResilientCache._();

  /// Persist a list of JSON-shaped maps. Silent on failure.
  static Future<void> putList(
      String boxName, String key, List<Map<String, dynamic>> rows) async {
    try {
      await hiveBox(boxName).put(key, rows);
    } catch (_) {
      // Caching is best-effort; never crash the request path.
    }
  }

  /// Read the most recent cached list. Returns null on miss / decode fail.
  static List<Map<String, dynamic>>? getList(String boxName, String key) {
    try {
      final raw = hiveBox(boxName).get(key);
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList();
      }
    } catch (_) {
      // Fall through to null.
    }
    return null;
  }

  /// Persist a single JSON-shaped map. Silent on failure.
  static Future<void> putMap(
      String boxName, String key, Map<String, dynamic> row) async {
    try {
      await hiveBox(boxName).put(key, row);
    } catch (_) {}
  }

  /// Read the most recent cached map. Returns null on miss / decode fail.
  static Map<String, dynamic>? getMap(String boxName, String key) {
    try {
      final raw = hiveBox(boxName).get(key);
      if (raw is Map) return Map<String, dynamic>.from(raw);
    } catch (_) {}
    return null;
  }
}
