class GalleryPhoto {
  final String id;
  final String projectId;
  final String signedUrl;
  final String? caption;
  final DateTime? takenAt;
  final DateTime? uploadedAt;
  final bool isDemo;

  const GalleryPhoto({
    required this.id,
    required this.projectId,
    required this.signedUrl,
    this.caption,
    this.takenAt,
    this.uploadedAt,
    this.isDemo = false,
  });

  factory GalleryPhoto.fromSupabase(
    Map<String, dynamic> j, {
    required String signedUrl,
  }) =>
      GalleryPhoto(
        id: (j['id'] ?? '') as String,
        projectId: (j['project_id'] ?? '') as String,
        signedUrl: signedUrl,
        caption: j['caption'] as String?,
        takenAt: j['taken_at'] != null
            ? DateTime.parse(j['taken_at'].toString())
            : null,
        uploadedAt: j['uploaded_at'] != null
            ? DateTime.parse(j['uploaded_at'].toString())
            : null,
      );
}
