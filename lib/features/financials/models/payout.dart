class Payout {
  final String id;
  final double amount;
  final String projectId;
  final String projectName;
  final String status; // pending | processed | on_hold
  final DateTime date;
  final String? utrRef;
  final bool isDemo;

  Payout({
    required this.id,
    required this.amount,
    required this.projectId,
    required this.projectName,
    required this.status,
    required this.date,
    this.utrRef,
    this.isDemo = false,
  });

  /// Reads a Supabase row produced by the join
  ///   payouts.select('id, amount, project_id, payout_date, utr, status, is_demo, projects(name)')
  factory Payout.fromSupabase(Map<String, dynamic> r) {
    final projectName = r['projects'] is Map
        ? ((r['projects'] as Map)['name'] ?? '') as String
        : '';
    return Payout(
      id: (r['id'] ?? '') as String,
      amount: (r['amount'] as num?)?.toDouble() ?? 0.0,
      projectId: (r['project_id'] ?? '') as String,
      projectName: projectName,
      status: (r['status'] ?? 'pending') as String,
      date: r['payout_date'] != null
          ? DateTime.parse(r['payout_date'].toString())
          : DateTime.now(),
      utrRef: r['utr'] as String?,
      isDemo: r['is_demo'] == true,
    );
  }

  factory Payout.fromJson(Map<String, dynamic> json) {
    return Payout(
      id: json['id'] ?? '',
      amount: (json['amount'] ?? 0).toDouble(),
      projectId: json['projectId'] ?? '',
      projectName: json['projectName'] ?? '',
      status: json['status'] ?? '',
      date:
          json['date'] != null ? DateTime.parse(json['date']) : DateTime.now(),
      utrRef: json['utrRef'],
      isDemo: json['isDemo'] == true,
    );
  }

  Payout copyWith({bool? isDemo}) => Payout(
        id: id,
        amount: amount,
        projectId: projectId,
        projectName: projectName,
        status: status,
        date: date,
        utrRef: utrRef,
        isDemo: isDemo ?? this.isDemo,
      );

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'amount': amount,
      'projectId': projectId,
      'projectName': projectName,
      'status': status,
      'date': date.toIso8601String(),
      'utrRef': utrRef,
      'isDemo': isDemo,
    };
  }
}
