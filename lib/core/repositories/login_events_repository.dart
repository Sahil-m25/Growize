import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:package_info_plus/package_info_plus.dart';

import 'package:arl_app/core/supabase/supabase_client.dart';

/// Append-only audit log of successful sign-ins. The client inserts a row
/// from the auth state listener; the row powers SecurityScreen's "Last
/// login" stamp and the login-history list.
class LoginEventsRepository {
  /// Insert a login event for the currently authenticated user. Silently
  /// no-ops when Supabase is unconfigured (demo mode) or there is no
  /// authenticated session yet.
  Future<void> recordLogin() async {
    final client = ArlSupabase.client;
    final uid = ArlSupabase.currentUserId;
    if (client == null || uid == null) return;

    final info = await PackageInfo.fromPlatform();
    final platform = _platformLabel();
    final device = _deviceLabel(platform);

    try {
      await client.from('login_events').insert({
        'user_id': uid,
        'device_label': device,
        'platform': platform,
        'app_version': '${info.version}+${info.buildNumber}',
      });
    } catch (_) {
      // Never block sign-in on audit log write failure.
    }
  }

  /// Most recent N rows for the current user, newest first.
  Future<List<Map<String, dynamic>>> myRecentLogins({int limit = 10}) async {
    final client = ArlSupabase.client;
    final uid = ArlSupabase.currentUserId;
    if (client == null || uid == null) return const [];
    final rows = await client
        .from('login_events')
        .select('id, occurred_at, device_label, platform, app_version')
        .eq('user_id', uid)
        .order('occurred_at', ascending: false)
        .limit(limit);
    return rows.cast<Map<String, dynamic>>();
  }

  String _platformLabel() {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:     return 'ios';
      case TargetPlatform.android: return 'android';
      case TargetPlatform.macOS:   return 'macos';
      case TargetPlatform.windows: return 'windows';
      case TargetPlatform.linux:   return 'linux';
      default:                     return 'unknown';
    }
  }

  String _deviceLabel(String platform) {
    switch (platform) {
      case 'ios':
        return 'iOS device';
      case 'android':
        return 'Android device';
      case 'web':
        return 'Web browser';
      case 'windows':
        return 'Windows PC';
      case 'macos':
        return 'Mac';
      case 'linux':
        return 'Linux PC';
      default:
        return 'Unknown device';
    }
  }
}
