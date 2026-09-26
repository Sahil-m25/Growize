import 'package:arl_app/core/supabase/storage_helper.dart';
import 'package:arl_app/core/supabase/supabase_client.dart';
import 'package:arl_app/core/constants/supabase_constants.dart';
import 'package:arl_app/features/gallery/models/gallery_photo.dart';

class GalleryRepository {
  Future<List<GalleryPhoto>> photos({String? projectId}) async {
    final client = ArlSupabase.client;
    if (client == null) return const [];
    var query = client
        .from('gallery_photos')
        .select('id, project_id, storage_path, caption, taken_at, uploaded_at');
    if (projectId != null) {
      query = query.eq('project_id', projectId);
    }
    final rows = await query.order('uploaded_at', ascending: false);

    // D.T1: Batch signed URLs instead of one-per-row.
    final paths = rows
        .map((r) => (r['storage_path'] ?? '') as String)
        .where((p) => p.isNotEmpty)
        .toList();
    final urls =
        await StorageHelper.signedUrlsForBucket(SupabaseConstants.galleryBucket, paths);

    final gallery = rows.map((r) {
      final path = (r['storage_path'] ?? '') as String;
      return GalleryPhoto.fromSupabase(r, signedUrl: urls[path] ?? '');
    }).toList();

    // Photos posted with farm updates also belong in the gallery, so an
    // investor sees every farm photo in one place. RLS on project_updates
    // already limits these to the investor's own projects.
    final updates = await _updatePhotos(projectId: projectId);
    final seen = gallery.map((p) => p.signedUrl).toSet();
    final all = [
      ...gallery,
      ...updates.where((p) => seen.add(p.signedUrl)),
    ]..sort((a, b) {
        final da = a.takenAt ?? a.uploadedAt ?? DateTime(1970);
        final db = b.takenAt ?? b.uploadedAt ?? DateTime(1970);
        return db.compareTo(da);
      });
    return all;
  }

  Future<List<GalleryPhoto>> _updatePhotos({String? projectId}) async {
    final client = ArlSupabase.client;
    if (client == null) return const [];
    try {
      var query = client
          .from('project_updates')
          .select('id, project_id, title, image_url, update_date, created_at')
          .not('image_url', 'is', null);
      if (projectId != null) {
        query = query.eq('project_id', projectId);
      }
      final rows = await query.order('update_date', ascending: false);
      return rows
          .where((r) => ((r['image_url'] ?? '') as String).isNotEmpty)
          .map((r) => GalleryPhoto(
                id: 'update-${r['id']}',
                projectId: (r['project_id'] ?? '') as String,
                signedUrl: r['image_url'] as String,
                caption: r['title'] as String?,
                takenAt: r['update_date'] != null
                    ? DateTime.tryParse(r['update_date'].toString())
                    : null,
                uploadedAt: r['created_at'] != null
                    ? DateTime.tryParse(r['created_at'].toString())
                    : null,
              ))
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
