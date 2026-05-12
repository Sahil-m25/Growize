class ProjectPhase {
  final String id;
  final String projectId;
  final String name;
  final String status; // done | current | pending
  final DateTime? phaseDate;
  final int sortOrder;
  final List<Map<String, dynamic>> subItems;
  final bool isDemo;

  const ProjectPhase({
    required this.id,
    required this.projectId,
    required this.name,
    required this.status,
    this.phaseDate,
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
        sortOrder: (j['sort_order'] as int?) ?? 0,
        subItems: (j['sub_items'] is List)
            ? List<Map<String, dynamic>>.from(j['sub_items'] as List)
            : const [],
        isDemo: j['isDemo'] == true,
      );

  bool get isDone => status == 'done';
  bool get isCurrent => status == 'current';
}
