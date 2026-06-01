class ProjectPhase {
  final String id;
  final String projectId;
  final String name;
  final String status; // done | current | pending
  final DateTime? phaseDate;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final int sortOrder;
  final List<Map<String, dynamic>> subItems;
  final bool isDemo;

  const ProjectPhase({
    required this.id,
    required this.projectId,
    required this.name,
    required this.status,
    this.phaseDate,
    this.startedAt,
    this.completedAt,
    this.sortOrder = 0,
    this.subItems = const [],
    this.isDemo = false,
  });

  factory ProjectPhase.fromJson(Map<String, dynamic> j) => ProjectPhase(
        id: (j['id'] ?? '') as String,
        projectId: (j['project_id'] ?? '') as String,
        name: (j['phase_name'] ?? j['name'] ?? '') as String,
        status: (j['status'] ?? 'pending') as String,
        phaseDate: j['phase_date'] != null
            ? DateTime.parse(j['phase_date'].toString())
            : (j['start_date'] != null
                ? DateTime.parse(j['start_date'].toString())
                : null),
        startedAt: j['started_at'] != null
            ? DateTime.parse(j['started_at'].toString())
            : null,
        completedAt: j['completed_at'] != null
            ? DateTime.parse(j['completed_at'].toString())
            : null,
        sortOrder: (j['sort_order'] as int?) ?? 0,
        subItems: (j['sub_items'] is List)
            ? List<Map<String, dynamic>>.from(j['sub_items'] as List)
            : const [],
        isDemo: j['isDemo'] == true,
      );

  bool get isDone => status == 'done';
  bool get isCurrent => status == 'current';

  /// Effective "completed on" — prefers the explicit `completed_at`
  /// column (migration 053) and falls back to the legacy
  /// `phase_date` for rows seeded before the split.
  DateTime? get effectiveCompletedAt =>
      completedAt ?? (isDone ? phaseDate : null);

  /// Effective "started on" — prefers the explicit `started_at`
  /// column and falls back to `phase_date` for the current phase
  /// when no explicit start has been seeded yet.
  DateTime? get effectiveStartedAt =>
      startedAt ?? (isCurrent ? phaseDate : null);
}
