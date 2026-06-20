class PortfolioSummary {
  final String investorName;
  final double totalInvested;
  final double totalReceived;
  final double pendingAmount;
  final int activeUnits;
  final int projectCount;
  final double avgAnnualYieldPct;
  final double nextPayoutAmount;
  final DateTime nextPayoutDate;
  final String? nextPayoutProjectName;
  final double roiPercent;
  final double annualReturns;
  final bool isDemo;

  PortfolioSummary({
    required this.investorName,
    required this.totalInvested,
    required this.totalReceived,
    required this.pendingAmount,
    required this.activeUnits,
    required this.nextPayoutAmount,
    required this.nextPayoutDate,
    required this.roiPercent,
    required this.annualReturns,
    this.projectCount = 0,
    this.avgAnnualYieldPct = 0,
    this.nextPayoutProjectName,
    this.isDemo = false,
  });

  /// Empty/zero portfolio for a real signed-in investor whose Zoho
  /// allocations haven't synced yet. Caller passes the investor's name.
  factory PortfolioSummary.empty({required String investorName}) =>
      PortfolioSummary(
        investorName: investorName,
        totalInvested: 0,
        totalReceived: 0,
        pendingAmount: 0,
        activeUnits: 0,
        projectCount: 0,
        nextPayoutAmount: 0,
        nextPayoutDate: DateTime.now().add(const Duration(days: 30)),
        roiPercent: 0,
        annualReturns: 0,
      );

  /// Reads from the Supabase `portfolio_summary` view.
  /// The view doesn't contain the investor's name (that's in `investors`),
  /// so the caller passes it through.
  ///
  /// NOTE: PostgREST returns PostgreSQL NUMERIC columns as JSON strings
  /// (e.g. "2500000.00") to avoid double-precision loss. Use _d() / _i()
  /// helpers that accept both num and String rather than `as num?` casts.
  factory PortfolioSummary.fromSupabase(
    Map<String, dynamic> r, {
    required String investorName,
    String? nextPayoutProjectName,
  }) {
    return PortfolioSummary(
      investorName: investorName,
      totalInvested: _d(r['total_invested']),
      totalReceived: _d(r['total_payouts_received']),
      pendingAmount: _d(r['total_capital_outstanding']),
      activeUnits: _i(r['total_units']),
      projectCount: _i(r['project_count']),
      avgAnnualYieldPct: _d(r['avg_annual_yield_pct']),
      nextPayoutAmount: _d(r['next_payout_amount']),
      nextPayoutDate: r['next_payout_date'] != null
          ? DateTime.parse(r['next_payout_date'].toString())
          : DateTime.now().add(const Duration(days: 30)),
      nextPayoutProjectName: nextPayoutProjectName,
      roiPercent: _d(r['roi_pct']),
      annualReturns: 0.0, // Populated client-side from FY-filtered payouts
    );
  }

  /// Safe double parser: handles both num (from integer columns) and
  /// String (from NUMERIC/DECIMAL columns which PostgREST encodes as JSON
  /// strings to preserve precision).
  static double _d(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  /// Safe int parser: same dual-type handling.
  static int _i(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  factory PortfolioSummary.fromJson(Map<String, dynamic> json) {
    return PortfolioSummary(
      investorName: json['investorName'] ?? '',
      totalInvested: (json['totalInvested'] ?? 0).toDouble(),
      totalReceived: (json['totalReceived'] ?? 0).toDouble(),
      pendingAmount: (json['pendingAmount'] ?? 0).toDouble(),
      activeUnits: json['activeUnits'] ?? 0,
      projectCount: json['projectCount'] ?? 0,
      nextPayoutAmount: (json['nextPayoutAmount'] ?? 0).toDouble(),
      nextPayoutDate: json['nextPayoutDate'] != null
          ? DateTime.parse(json['nextPayoutDate'])
          : DateTime.now(),
      nextPayoutProjectName: json['nextPayoutProjectName'] as String?,
      roiPercent: (json['roiPercent'] ?? 0).toDouble(),
      annualReturns: (json['annualReturns'] ?? 0).toDouble(),
      isDemo: json['isDemo'] == true,
    );
  }

  PortfolioSummary copyWith({
    bool? isDemo,
    String? nextPayoutProjectName,
    int? projectCount,
    double? avgAnnualYieldPct,
    double? roiPercent,
  }) =>
      PortfolioSummary(
        investorName: investorName,
        totalInvested: totalInvested,
        totalReceived: totalReceived,
        pendingAmount: pendingAmount,
        activeUnits: activeUnits,
        projectCount: projectCount ?? this.projectCount,
        avgAnnualYieldPct: avgAnnualYieldPct ?? this.avgAnnualYieldPct,
        nextPayoutAmount: nextPayoutAmount,
        nextPayoutDate: nextPayoutDate,
        nextPayoutProjectName:
            nextPayoutProjectName ?? this.nextPayoutProjectName,
        roiPercent: roiPercent ?? this.roiPercent,
        annualReturns: annualReturns,
        isDemo: isDemo ?? this.isDemo,
      );

  Map<String, dynamic> toJson() => {
        'investorName': investorName,
        'totalInvested': totalInvested,
        'totalReceived': totalReceived,
        'pendingAmount': pendingAmount,
        'activeUnits': activeUnits,
        'projectCount': projectCount,
        'nextPayoutAmount': nextPayoutAmount,
        'nextPayoutDate': nextPayoutDate.toIso8601String(),
        'nextPayoutProjectName': nextPayoutProjectName,
        'roiPercent': roiPercent,
        'annualReturns': annualReturns,
        'isDemo': isDemo,
      };
}
