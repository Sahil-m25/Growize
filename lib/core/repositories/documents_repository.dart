import 'package:arl_app/core/constants/supabase_constants.dart';
import 'package:arl_app/core/offline/hive_cache.dart';
import 'package:arl_app/core/offline/resilient_cache.dart';
import 'package:arl_app/core/supabase/storage_helper.dart';
import 'package:arl_app/core/supabase/supabase_client.dart';
import 'package:arl_app/features/documents/models/document.dart';

class DocumentsRepository {
  static const _box = HiveBoxes.documents;
  static const _kDocs = 'documents';
  static const _kUrlPrefix = 'doc_url_';

  Future<List<InvestorDocument>> myDocuments() async {
    final client = ArlSupabase.client;
    if (client == null) return _readCache();

    try {
      final rows = await client
          .from('documents')
          .select()
          .order('uploaded_at', ascending: false);
      final list = (rows as List).cast<Map<String, dynamic>>();

      // Batch signed URLs (best-effort).
      final paths = list
          .map((r) => (r['storage_path'] ?? '') as String)
          .where((p) => p.isNotEmpty)
          .toList();
      Map<String, String> urls = const {};
      try {
        urls = await StorageHelper.signedUrlsForBucket(
            SupabaseConstants.documentsBucket, paths);
      } catch (_) {
        // Storage call failed — fall through with empty url map.
      }

      // Persist row metadata + last-known signed URLs so an offline
      // re-open can still display a list.
      await ResilientCache.putList(_box, _kDocs, list);
      for (final entry in urls.entries) {
        await hiveBox(_box).put('$_kUrlPrefix${entry.key}', entry.value);
      }

      return list.map((r) {
        final path = (r['storage_path'] ?? '') as String;
        return InvestorDocument.fromSupabase(r, signedUrl: urls[path] ?? '');
      }).toList();
    } catch (_) {
      return _readCache();
    }
  }

  List<InvestorDocument> _readCache() {
    final cached = ResilientCache.getList(_box, _kDocs);
    if (cached == null) return const [];
    return cached.map((r) {
      final path = (r['storage_path'] ?? '') as String;
      String url = '';
      try {
        final raw = hiveBox(_box).get('$_kUrlPrefix$path');
        if (raw is String) url = raw;
      } catch (_) {}
      return InvestorDocument.fromSupabase(r, signedUrl: url);
    }).toList();
  }
}
