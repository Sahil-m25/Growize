/// Monthly Updates row from `public.project_updates`.
///
/// One narrative post per project per month-ish, shown on the Project
/// Detail screen. Distinct from `project_phases` (which models milestone
/// gates with a checklist) — updates are free-form posts with a title,
/// body and optional cover image.
class ProjectUpdate {
  final String id;
  final String projectId;
  final DateTime updateDate;
  final String title;
  final String body;
  final String? imageUrl;

  const ProjectUpdate({
    required this.id,
    required this.projectId,
    required this.updateDate,
    required this.title,
    required this.body,
    this.imageUrl,
  });

  factory ProjectUpdate.fromJson(Map<String, dynamic> j) {
    final dateStr = (j['update_date'] ?? '').toString();
    DateTime date;
    try {
      date = DateTime.parse(dateStr);
    } catch (_) {
      date = DateTime.now();
    }
    return ProjectUpdate(
      id: (j['id'] ?? '') as String,
      projectId: (j['project_id'] ?? '') as String,
      updateDate: date,
      title: (j['title'] ?? '') as String,
      body: (j['body'] ?? '') as String,
      imageUrl: j['image_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'project_id': projectId,
        'update_date': updateDate.toIso8601String(),
        'title': title,
        'body': body,
        'image_url': imageUrl,
      };
}
