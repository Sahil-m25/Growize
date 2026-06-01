import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show HttpMethod;

import 'package:arl_app/core/constants/supabase_constants.dart';
import 'package:arl_app/core/supabase/supabase_client.dart';

/// Result of a successful version check that found a newer release.
///
/// Returned by [AppVersionCheck.check]. `null` from the check means the
/// app is on the latest version, the check failed, or the app is in
/// demo / unconfigured mode.
@immutable
class AppUpdate {
  final String versionName;
  final int versionCode;
  final String? apkUrl;
  final String? webUrl;
  final String? releaseNotes;
  final bool isCritical;

  const AppUpdate({
    required this.versionName,
    required this.versionCode,
    required this.apkUrl,
    required this.webUrl,
    required this.releaseNotes,
    required this.isCritical,
  });
}

/// Compares the running app's build number against the latest row in
/// the Supabase `app_releases` table (via the `latest-app-version`
/// edge function). Designed to be best-effort: any failure returns
/// null so the app keeps functioning without nagging the user.
///
/// Results are cached for the lifetime of the process — version
/// changes between launches, not between screen pushes.
class AppVersionCheck {
  AppVersionCheck._();

  static AppUpdate? _cached;
  static bool _hasRun = false;
  static Future<AppUpdate?>? _inflight;

  /// Public entry point. Returns the latest update info if the running
  /// build is behind, or `null` if up to date / unable to check.
  ///
  /// Safe to call concurrently — repeated calls share a single in-flight
  /// future and subsequent calls return the cached result.
  static Future<AppUpdate?> check() {
    if (_hasRun) return Future.value(_cached);
    return _inflight ??= _run().whenComplete(() => _inflight = null);
  }

  /// Test-only — clears the in-memory cache so the next [check] call
  /// re-runs the network request.
  @visibleForTesting
  static void resetForTest() {
    _cached = null;
    _hasRun = false;
    _inflight = null;
  }

  static Future<AppUpdate?> _run() async {
    try {
      // In demo / unconfigured mode there's nothing to check against.
      final client = ArlSupabase.client;
      if (client == null) {
        _hasRun = true;
        _cached = null;
        return null;
      }

      // Resolve the running build number. package_info_plus exposes
      // this as a string — we tolerate non-numeric (e.g. "1.0") by
      // treating it as 0 so we'd still surface a known update.
      final pkgInfo = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(pkgInfo.buildNumber) ?? 0;

      // Invoke the edge function. Uses the configured anon key under
      // the hood; verify_jwt=false on the function so an unauthenticated
      // cold-start check still works.
      final res = await client.functions.invoke(
        SupabaseConstants.fnLatestAppVersion,
        method: HttpMethod.get,
      );

      if (res.status < 200 || res.status >= 300) {
        _hasRun = true;
        _cached = null;
        return null;
      }

      final data = res.data;
      if (data is! Map) {
        _hasRun = true;
        _cached = null;
        return null;
      }

      final latestCode = (data['version_code'] as num?)?.toInt() ?? 0;
      if (latestCode <= currentBuild) {
        _hasRun = true;
        _cached = null;
        return null;
      }

      final update = AppUpdate(
        versionName: (data['version_name'] as String?) ?? '',
        versionCode: latestCode,
        apkUrl: data['apk_url'] as String?,
        webUrl: data['web_url'] as String?,
        releaseNotes: data['release_notes'] as String?,
        isCritical: (data['is_critical'] as bool?) ?? false,
      );

      _hasRun = true;
      _cached = update;
      return update;
    } catch (e, st) {
      // Best-effort: swallow everything so a broken/blocked version
      // check never bricks the app.
      if (kDebugMode) {
        debugPrint('AppVersionCheck failed: $e\n$st');
      }
      _hasRun = true;
      _cached = null;
      return null;
    }
  }
}
