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
  factory PortfolioSummary.fromSupabase(
    Map<String, dynamic> r, {
    required String investorName,
    String? nextPayoutProjectName,
  }) {
    return PortfolioSummary(
      investorName: investorName,
      totalInvested: (r['total_invested'] as num?)?.toDouble() ?? 0.0,
      totalReceived:
          (r['total_payouts_received'] as num?)?.toDouble() ?? 0.0,
      pendingAmount:
          (r['total_capital_outstanding'] as num?)?.toDouble() ?? 0.0,
      activeUnits: (r['total_units'] as num?)?.toInt() ?? 0,
      projectCount: (r['project_count'] as num?)?.toInt() ?? 0,
      avgAnnualYieldPct:
          (r['avg_annual_yield_pct'] as num?)?.toDouble() ?? 0.0,
      nextPayoutAmount:
          (r['next_payout_amount'] as num?)?.toDouble() ?? 0.0,
      nextPayoutDate: r['next_payout_date'] != null
          ? DateTime.parse(r['next_payout_date'].toString())
          : DateTime.now().add(const Duration(days: 30)),
      nextPayoutProjectName: nextPayoutProjectName,
      roiPercent: (r['roi_pct'] as num?)?.toDouble() ?? 0.0,
      annualReturns: 0.0, // Populated client-side from FY-filtered payouts
    );
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
        roiPercent: roiPercent,
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
