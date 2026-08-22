class ArlNotification {
  final String id;
  // DB values, per the notifications_type_check constraint:
  //   payout | photo | ticket | reminder | milestone | kyc | exit |
  //   bank_change | phase_update | document | new_project
  // (phase_update / document / new_project added by migration 066)
  final String type;
  final String title;
  final String body;
  final bool isRead;
  final DateTime createdAt;
  final Map<String, dynamic>? metadata;
  final bool isDemo;

  const ArlNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.isRead,
    required this.createdAt,
    this.metadata,
    this.isDemo = false,
  });

  factory ArlNotification.fromSupabase(Map<String, dynamic> j) =>
      ArlNotification(
        id: (j['id'] ?? '') as String,
        type: (j['type'] ?? 'reminder') as String,
        title: (j['title'] ?? '') as String,
        body: (j['body'] ?? '') as String,
        isRead: j['read_at'] != null,
        createdAt: j['created_at'] != null
            ? DateTime.parse(j['created_at'].toString())
            : DateTime.now(),
        metadata: j['metadata'] is Map
            ? Map<String, dynamic>.from(j['metadata'] as Map)
            : null,
      );

  /// Maps DB notification types to display tints used by the UI.
  /// The HTML mock used `warning|success|payout|info`; DB uses
  /// `payout|photo|ticket|reminder|milestone`. This is the single
  /// place that translation lives.
  String get displayType {
    switch (type) {
      case 'payout':
        return 'payout';
      case 'photo':
        return 'success';
      // Stage / milestone progress on a project. `phase_update` is
      // written by the migration-066 trigger on project_phases;
      // `milestone` is the older name kept for rows seeded before it.
      case 'milestone':
      case 'phase_update':
        return 'milestone';
      case 'ticket':
        return 'info';
      case 'document':
        return 'info';
      case 'reminder':
        return 'warning';
      default:
        return 'info';
    }
  }
}
