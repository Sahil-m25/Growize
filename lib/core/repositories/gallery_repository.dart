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

    return rows.map((r) {
      final path = (r['storage_path'] ?? '') as String;
      return GalleryPhoto.fromSupabase(r, signedUrl: urls[path] ?? '');
    }).toList();
  }
}
