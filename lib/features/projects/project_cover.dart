import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:arl_app/core/supabase/storage_helper.dart';
import 'package:arl_app/core/supabase/supabase_client.dart';

/// Banner photo for a project: `projects.cover_image_path`, a file in the
/// private `arl-gallery` bucket, returned as a short-lived signed URL.
/// Null when no cover is set (the banner then shows the initials).
final projectCoverUrlProvider =
    FutureProvider.family<String?, String>((ref, projectId) async {
  final client = ArlSupabase.client;
  if (client == null || projectId.isEmpty || projectId.startsWith('demo:')) {
    return null;
  }
  try {
    final row = await client
        .from('projects')
        .select('cover_image_path')
        .eq('id', projectId)
        .maybeSingle();
    final path = (row?['cover_image_path'] ?? '') as String;
    if (path.isEmpty) return null;
    return await StorageHelper.signedUrlForGalleryPhoto(path);
  } catch (_) {
    return null;
  }
});
