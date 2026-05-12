/// Mirror of `investor_units` row (LLP_UnitAllocation_Module from Zoho).
class InvestorUnit {
  final String id;
  final String projectId;
  final int issuedUnits;
  final int reservedUnits;
  final double unitPrice;
  final double capitalInvested;
  final double capitalOutstanding;
  final double capitalReturns;
  final double totalAmountReceivable;
  final double totalAmountReceived;
  final double tokenAdvanceAmount;
  final double annualYieldPct;
  final String allocationStatus;
  final String customerStatus;
  final DateTime? investmentDate;
  final DateTime? nextPayoutDate;
  final bool isDemo;

  const InvestorUnit({
    required this.id,
    required this.projectId,
    required this.issuedUnits,
    required this.reservedUnits,
    required this.unitPrice,
    required this.capitalInvested,
    required this.capitalOutstanding,
    required this.capitalReturns,
    required this.totalAmountReceivable,
    required this.totalAmountReceived,
    required this.tokenAdvanceAmount,
    required this.annualYieldPct,
    required this.allocationStatus,
    required this.customerStatus,
    this.investmentDate,
    this.nextPayoutDate,
    this.isDemo = false,
  });

  factory InvestorUnit.fromJson(Map<String, dynamic> j) => InvestorUnit(
        id: (j['id'] ?? '') as String,
        projectId: (j['project_id'] ?? '') as String,
        issuedUnits: (j['issued_units'] as int?) ?? 0,
        reservedUnits: (j['reserved_units'] as int?) ?? 0,
        unitPrice: (j['unit_price'] as num?)?.toDouble() ?? 0.0,
        capitalInvested: (j['capital_invested'] as num?)?.toDouble() ?? 0.0,
        capitalOutstanding:
            (j['capital_outstanding'] as num?)?.toDouble() ?? 0.0,
        capitalReturns: (j['capital_returns'] as num?)?.toDouble() ?? 0.0,
        totalAmountReceivable:
            (j['total_amount_receivable'] as num?)?.toDouble() ?? 0.0,
        totalAmountReceived:
            (j['total_amount_received'] as num?)?.toDouble() ?? 0.0,
        tokenAdvanceAmount:
            (j['token_advance_amount'] as num?)?.toDouble() ?? 0.0,
        annualYieldPct: (j['annual_yield_pct'] as num?)?.toDouble() ?? 0.0,
        allocationStatus: (j['allocation_status'] ?? '') as String,
        customerStatus: (j['customer_status'] ?? '') as String,
        investmentDate: j['investment_date'] != null
            ? DateTime.parse(j['investment_date'].toString())
            : null,
        nextPayoutDate: j['next_payout_date'] != null
            ? DateTime.parse(j['next_payout_date'].toString())
            : null,
        isDemo: j['isDemo'] == true,
      );
}
