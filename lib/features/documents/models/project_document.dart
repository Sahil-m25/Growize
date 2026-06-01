/// Project-level document — backed by `public.project_documents`
/// (migration 054). One row per file; visibility is enforced server-side
/// via RLS (investors with a non-zero, non-deleted allocation in the
/// project, or any authenticated user when `is_public` is true).
///
/// Distinct from [InvestorDocument] which holds per-investor KYC,
/// contracts and payout receipts in the `documents` table.
class ProjectDocument {
  /// Primary key (uuid).
  final String id;

  /// FK to `projects.id` — the project this document belongs to.
  final String projectId;

  /// Path inside the `arl-documents` storage bucket. Used to mint a
  /// short-lived signed URL via [StorageHelper.signedUrlsForBucket].
  final String storagePath;

  /// Display title (e.g. "LLP Agreement v3").
  final String title;

  /// Loose category label — agreement / brochure / report /
  /// certification / financial / regulatory / update / general.
  /// Used to colour the category pill in the UI.
  final String category;

  /// Wall-clock upload time. Drives the "uploaded MMM dd, yyyy" caption.
  final DateTime uploadedAt;

  /// When true, the row is visible to every authenticated user
  /// regardless of allocation (company-wide briefings).
  final bool isPublic;

  /// Short-lived signed URL for the file in `arl-documents`. Empty
  /// string when the storage call failed or the file is missing —
  /// callers should treat empty as "URL unavailable".
  final String signedUrl;

  const ProjectDocument({
    required this.id,
    required this.projectId,
    required this.storagePath,
    required this.title,
    required this.category,
    required this.uploadedAt,
    required this.isPublic,
    required this.signedUrl,
  });

  factory ProjectDocument.fromSupabase(
    Map<String, dynamic> j, {
    required String signedUrl,
  }) {
    return ProjectDocument(
      id: (j['id'] ?? '') as String,
      projectId: (j['project_id'] ?? '') as String,
      storagePath: (j['storage_path'] ?? '') as String,
      title: (j['title'] ?? '') as String,
      category: (j['category'] ?? 'general') as String,
      uploadedAt: j['uploaded_at'] != null
          ? DateTime.parse(j['uploaded_at'].toString())
          : DateTime.fromMillisecondsSinceEpoch(0),
      isPublic: (j['is_public'] ?? false) as bool,
      signedUrl: signedUrl,
    );
  }
}
