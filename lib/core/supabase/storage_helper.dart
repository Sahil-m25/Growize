import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:arl_app/core/constants/supabase_constants.dart';
import 'package:arl_app/core/supabase/supabase_client.dart';

/// Generates short-lived signed URLs for private bucket files.
/// Caches them in-memory until close to expiry to avoid hammering the API
/// every time the gallery rebuilds.
class StorageHelper {
  static final Map<String, _Signed> _cache = {};
  static const Duration _ttl = Duration(minutes: 50); // signed URL is 60min

  static Future<String?> signedUrlForDocument(String storagePath) =>
      _signed(SupabaseConstants.documentsBucket, storagePath);

  static Future<String?> signedUrlForGalleryPhoto(String storagePath) =>
      _signed(SupabaseConstants.galleryBucket, storagePath);

  /// D.T1: Batch signed URL generation.
  /// Fetches multiple signed URLs in a single API call instead of one per path.
  static Future<Map<String, String>> signedUrlsForBucket(
    String bucket,
    List<String> paths,
  ) async {
    final client = ArlSupabase.client;
    if (client == null || paths.isEmpty) return {};

    // Filter out already-cached paths that haven't expired.
    final fresh = paths.where((p) {
      final key = '$bucket::$p';
      final cached = _cache[key];
      return cached == null || cached.expiresAt.isBefore(DateTime.now());
    }).toList();

    // Batch fetch fresh URLs.
    if (fresh.isNotEmpty) {
      try {
        final results = await client.storage
            .from(bucket)
            .createSignedUrls(fresh, _ttl.inSeconds);
        for (final r in results) {
          final key = '$bucket::${r.path}';
          _cache[key] = _Signed(r.signedUrl, DateTime.now().add(_ttl));
        }
      } on StorageException {
        // If batch fetch fails, return what we have cached.
      }
    }

    // Return all URLs (cached + fresh).
    return {for (final p in paths) p: _cache['$bucket::$p']?.url ?? ''};
  }

  static Future<String?> _signed(String bucket, String path) async {
    final client = ArlSupabase.client;
    if (client == null || path.isEmpty) return null;

    final key = '$bucket::$path';
    final cached = _cache[key];
    if (cached != null && cached.expiresAt.isAfter(DateTime.now())) {
      return cached.url;
    }
    try {
      final url = await client.storage
          .from(bucket)
          .createSignedUrl(path, _ttl.inSeconds);
      _cache[key] = _Signed(url, DateTime.now().add(_ttl));
      return url;
    } on StorageException {
      return null;
    }
  }

  static void clear() => _cache.clear();
}

class _Signed {
  final String url;
  final DateTime expiresAt;
  _Signed(this.url, this.expiresAt);
}
