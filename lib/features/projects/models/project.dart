/// Project model — represents a single farm / LLP an investor has units in.
///
/// Two factories:
///   - [fromSupabase] reads the Supabase `projects` row and derives display
///     fields (initials, progress, monthOfContract) the DB doesn't store.
///   - [fromJson] is kept for legacy mock-data shape compatibility.
///
/// ─── PRIVACY: raw coordinates never leave LocationScreen ─────────────
/// Reads go through `public.projects_public` — a SECURITY INVOKER view
/// that intentionally omits `latitude` / `longitude`. See
/// `supabase/migrations/20260513000000_034_projects_public_view.sql`
/// and audit finding S-002 in `docs/security_audit_2026-05-13.md`.
///
/// This model has no `latitude` / `longitude` fields and must stay that
/// way. If a future LocationScreen iteration genuinely needs the raw
/// coords (e.g. to draw a precise marker the investor explicitly
/// requested), it must:
///   1) Query `public.projects` directly from that screen only.
///   2) Hold the coords in a dedicated `LocationCoords` value, not on
///      this model.
///   3) Document the carve-out in a comment block at the call site,
///      with a pointer back to S-002 in the audit doc.
class Project {
  final String id;
  final String name;
  final String cropType;
  final String location;
  final String status;
  final DateTime startDate;
  final DateTime endDate;
  final int totalUnits;
  final double investedAmount;
  final double progressPercent;
  final int monthOfContract;
  final int totalMonths;
  final String colorHex;
  final String initials;
  final double nextPayoutAmount;
  final DateTime? nextPayoutDate;
  final String cropEmoji;

  /// True for sample data shown when no real rows exist yet.
  /// UI shows a "Sample" pill when this is true.
  final bool isDemo;

  Project({
    required this.id,
    required this.name,
    required this.cropType,
    required this.location,
    required this.status,
    required this.startDate,
    required this.endDate,
    required this.totalUnits,
    required this.investedAmount,
    required this.progressPercent,
    required this.monthOfContract,
    required this.totalMonths,
    required this.colorHex,
    required this.initials,
    required this.nextPayoutAmount,
    required this.nextPayoutDate,
    required this.cropEmoji,
    this.isDemo = false,
  });

  factory Project.fromSupabase(Map<String, dynamic> r) {
    final name = (r['name'] ?? '') as String;
    final launch = _parseDate(r['launch_year']) ??
        _parseDate(r['updated_at']) ??
        DateTime.now();
    // No explicit end date in DB — assume 5y contract from launch_year.
    final endDate = DateTime(launch.year + 5, launch.month, launch.day);
    final months =
        (endDate.year - launch.year) * 12 + (endDate.month - launch.month);
    final monthsElapsed =
        _monthsBetween(launch, DateTime.now()).clamp(0, months);

    return Project(
      id: (r['id'] ?? '') as String,
      name: name,
      // `cropType` and `cropEmoji` aren't on `projects` directly — they
      // come from the `crops` table. We leave them empty here; the projects
      // provider can join `crops` separately if needed.
      cropType: (r['tier'] ?? '') as String,
      location: _composeLocation(r),
      status: (r['status'] ?? 'active') as String,
      startDate: launch,
      endDate: endDate,
      totalUnits: (r['total_units'] as int?) ?? 0,
      investedAmount: (r['total_ticket_size'] as num?)?.toDouble() ?? 0.0,
      progressPercent: 0, // derived from project_phases if needed
      monthOfContract: monthsElapsed,
      totalMonths: months > 0 ? months : 60,
      colorHex: (r['color_hex'] ?? '#3C5152') as String,
      initials: _initialsOf(name),
      nextPayoutAmount: 0.0, // populated via portfolio_summary view
      nextPayoutDate: null,
      cropEmoji: '🌱',
    );
  }

  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      cropType: json['cropType'] ?? '',
      location: json['location'] ?? '',
      status: json['status'] ?? '',
      startDate: json['startDate'] != null
          ? DateTime.parse(json['startDate'])
          : DateTime.now(),
      endDate: json['endDate'] != null
          ? DateTime.parse(json['endDate'])
          : DateTime.now(),
      totalUnits: json['totalUnits'] ?? 0,
      investedAmount: (json['investedAmount'] ?? 0).toDouble(),
      progressPercent: (json['progressPercent'] ?? 0).toDouble(),
      monthOfContract: json['monthOfContract'] ?? 0,
      totalMonths: json['totalMonths'] ?? 0,
      colorHex: json['colorHex'] ?? '#3C5152',
      initials: json['initials'] ?? '',
      nextPayoutAmount: (json['nextPayoutAmount'] ?? 0).toDouble(),
      nextPayoutDate: json['nextPayoutDate'] != null
          ? DateTime.parse(json['nextPayoutDate'])
          : null,
      cropEmoji: json['cropEmoji'] ?? '',
      isDemo: json['isDemo'] == true,
    );
  }

  Project copyWith({bool? isDemo, double? progressPercent}) => Project(
        id: id,
        name: name,
        cropType: cropType,
        location: location,
        status: status,
        startDate: startDate,
        endDate: endDate,
        totalUnits: totalUnits,
        investedAmount: investedAmount,
        progressPercent: progressPercent ?? this.progressPercent,
        monthOfContract: monthOfContract,
        totalMonths: totalMonths,
        colorHex: colorHex,
        initials: initials,
        nextPayoutAmount: nextPayoutAmount,
        nextPayoutDate: nextPayoutDate,
        cropEmoji: cropEmoji,
        isDemo: isDemo ?? this.isDemo,
      );

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'cropType': cropType,
      'location': location,
      'status': status,
      'startDate': startDate.toIso8601String(),
      'endDate': endDate.toIso8601String(),
      'totalUnits': totalUnits,
      'investedAmount': investedAmount,
      'progressPercent': progressPercent,
      'monthOfContract': monthOfContract,
      'totalMonths': totalMonths,
      'colorHex': colorHex,
      'initials': initials,
      'nextPayoutAmount': nextPayoutAmount,
      'nextPayoutDate': nextPayoutDate?.toIso8601String(),
      'cropEmoji': cropEmoji,
      'isDemo': isDemo,
    };
  }
}

DateTime? _parseDate(dynamic v) {
  if (v == null) return null;
  try {
    return DateTime.parse(v.toString());
  } catch (_) {
    return null;
  }
}

int _monthsBetween(DateTime a, DateTime b) =>
    (b.year - a.year) * 12 + (b.month - a.month);

String _composeLocation(Map<String, dynamic> r) {
  final city = (r['city'] ?? '') as String;
  final state = (r['state'] ?? '') as String;
  return [city, state].where((s) => s.isNotEmpty).join(', ');
}

String _initialsOf(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.first.isEmpty) return '';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts[0][0] + parts[1][0]).toUpperCase();
}
