import 'package:arl_app/core/constants/supabase_constants.dart';
import 'package:arl_app/core/offline/hive_cache.dart';
import 'package:arl_app/core/offline/resilient_cache.dart';
import 'package:arl_app/core/supabase/storage_helper.dart';
import 'package:arl_app/core/supabase/supabase_client.dart';
import 'package:arl_app/features/documents/models/document.dart';
import 'package:arl_app/features/documents/models/project_document.dart';

class DocumentsRepository {
  static const _box = HiveBoxes.documents;
  static const _kDocs = 'documents';
  static const _kUrlPrefix = 'doc_url_';

  // Project-document cache keys. Per-project lists live under
  // `project_documents_<projectId>`; the union (all docs visible to
  // the current investor) lives under `project_documents_all` so the
  // Documents tab can render straight out of cache while the network
  // call is in flight.
  static const _kProjectDocsAll = 'project_documents_all';
  static const _kProjectDocsPrefix = 'project_documents_';

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

  /// Reads every project document visible to the current investor. RLS
  /// on `project_documents` filters server-side to (is_public=true OR
  /// investor has a non-zero allocation in the project), so a bare
  /// SELECT is safe — there is no client-side WHERE to add.
  ///
  /// Used by the Documents tab to render the "Project Documents"
  /// section grouped by project.
  Future<List<ProjectDocument>> myProjectDocuments() async {
    final client = ArlSupabase.client;
    if (client == null) return _readProjectDocsCache(_kProjectDocsAll);

    try {
      final rows = await client
          .from('project_documents')
          .select()
          .order('sort_order', ascending: true)
          .order('uploaded_at', ascending: false);
      final list = (rows as List).cast<Map<String, dynamic>>();
      return _materialiseProjectDocs(list, cacheKey: _kProjectDocsAll);
    } catch (_) {
      return _readProjectDocsCache(_kProjectDocsAll);
    }
  }

  /// Reads the project documents for a single project. The RLS policy
  /// still enforces the allocation check, so an investor without units
  /// in [projectId] will simply get an empty list.
  ///
  /// Used by the project detail screen's "Project Documents" row.
  Future<List<ProjectDocument>> projectDocuments(String projectId) async {
    if (projectId.isEmpty) return const [];
    final cacheKey = '$_kProjectDocsPrefix$projectId';
    final client = ArlSupabase.client;
    if (client == null) return _readProjectDocsCache(cacheKey);

    try {
      final rows = await client
          .from('project_documents')
          .select()
          .eq('project_id', projectId)
          .order('sort_order', ascending: true)
          .order('uploaded_at', ascending: false);
      final list = (rows as List).cast<Map<String, dynamic>>();
      return _materialiseProjectDocs(list, cacheKey: cacheKey);
    } catch (_) {
      return _readProjectDocsCache(cacheKey);
    }
  }

  /// Common path: batch-sign URLs, persist to Hive, then return a
  /// fully-populated [ProjectDocument] list. Centralised so the
  /// `myProjectDocuments` / `projectDocuments` variants stay tiny.
  Future<List<ProjectDocument>> _materialiseProjectDocs(
    List<Map<String, dynamic>> rows, {
    required String cacheKey,
  }) async {
    final paths = rows
        .map((r) => (r['storage_path'] ?? '') as String)
        .where((p) => p.isNotEmpty)
        .toList();
    Map<String, String> urls = const {};
    try {
      urls = await StorageHelper.signedUrlsForBucket(
          SupabaseConstants.documentsBucket, paths);
    } catch (_) {
      // Best-effort — UI handles empty signed URLs gracefully.
    }

    await ResilientCache.putList(_box, cacheKey, rows);
    for (final entry in urls.entries) {
      await hiveBox(_box).put('$_kUrlPrefix${entry.key}', entry.value);
    }

    return rows.map((r) {
      final path = (r['storage_path'] ?? '') as String;
      return ProjectDocument.fromSupabase(r, signedUrl: urls[path] ?? '');
    }).toList();
  }

  /// Offline fallback for project documents — pulls last-known rows
  /// out of Hive and re-uses the cached signed URLs (may be expired
  /// but the viewer's missing-file fallback handles that).
  List<ProjectDocument> _readProjectDocsCache(String cacheKey) {
    final cached = ResilientCache.getList(_box, cacheKey);
    if (cached == null) return const [];
    return cached.map((r) {
      final path = (r['storage_path'] ?? '') as String;
      String url = '';
      try {
        final raw = hiveBox(_box).get('$_kUrlPrefix$path');
        if (raw is String) url = raw;
      } catch (_) {}
      return ProjectDocument.fromSupabase(r, signedUrl: url);
    }).toList();
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
