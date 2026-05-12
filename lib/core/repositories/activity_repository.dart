import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:arl_app/core/offline/hive_cache.dart';
import 'package:arl_app/core/offline/resilient_cache.dart';
import 'package:arl_app/core/supabase/supabase_client.dart';
import 'package:arl_app/features/activity/models/notification.dart';

class ActivityRepository {
  static const _box = HiveBoxes.activity;
  static const _kNotifications = 'notifications';
  static const _kUnreadCount = 'unread_count';

  Future<List<ArlNotification>> notifications({int limit = 50}) async {
    final client = ArlSupabase.client;
    if (client == null) return _readCache();
    try {
      final rows = await client
          .from('notifications')
          .select()
          .order('created_at', ascending: false)
          .limit(limit);
      final list = (rows as List).cast<Map<String, dynamic>>();
      await ResilientCache.putList(_box, _kNotifications, list);
      return list
          .map<ArlNotification>((r) => ArlNotification.fromSupabase(r))
          .toList();
    } catch (_) {
      return _readCache();
    }
  }

  List<ArlNotification> _readCache() {
    final cached = ResilientCache.getList(_box, _kNotifications);
    if (cached == null) return const [];
    return cached
        .map<ArlNotification>((r) => ArlNotification.fromSupabase(r))
        .toList();
  }

  /// Uses count: exact for efficiency. Falls back to cached count on
  /// failure.
  Future<int> unreadCount() async {
    final client = ArlSupabase.client;
    if (client == null) return _readUnreadCache();
    try {
      final res = await client
          .from('notifications')
          .select()
          .filter('read_at', 'is', null)
          .count(CountOption.exact);
      await hiveBox(_box).put(_kUnreadCount, res.count);
      return res.count;
    } catch (_) {
      return _readUnreadCache();
    }
  }

  int _readUnreadCache() {
    try {
      final raw = hiveBox(_box).get(_kUnreadCount);
      if (raw is int) return raw;
    } catch (_) {}
    return 0;
  }

  Future<void> markRead(String id) async {
    final client = ArlSupabase.client;
    if (client == null) return;
    try {
      await client
          .from('notifications')
          .update({'read_at': DateTime.now().toIso8601String()}).eq('id', id);
    } catch (_) {
      // Best-effort write; ignore so the UI optimistic-update sticks.
    }
  }

  Future<void> markAllRead() async {
    final client = ArlSupabase.client;
    if (client == null) return;
    try {
      await client
          .from('notifications')
          .update({'read_at': DateTime.now().toIso8601String()}).filter(
              'read_at', 'is', null);
    } catch (_) {}
  }
}
