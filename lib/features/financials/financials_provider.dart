import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arl_app/core/auth/session_manager.dart';
import 'package:arl_app/core/connectivity/sync_state.dart';
import 'package:arl_app/core/mock/demo_data.dart';
import 'package:arl_app/core/providers/repositories.dart';
import 'package:arl_app/features/auth/auth_provider.dart';
import 'package:arl_app/features/financials/models/payout.dart';
import 'package:arl_app/features/home/home_provider.dart';
import 'package:arl_app/features/home/models/portfolio_summary.dart';
import 'package:arl_app/features/projects/projects_provider.dart';

/// B.T6: Payouts ledger.
/// If authenticated (currentInvestorProvider has value), always show real
/// payouts (even an empty list — show "No payouts yet").
/// Demo payouts are reserved for the unauthenticated design-preview flow.
final payoutsProvider = FutureProvider<List<Payout>>((ref) async {
  // Rebuild on auth changes — don't keep demo payouts cached after sign-in.
  ref.watch(authStateProvider);

  final selectedId = ref.watch(selectedProjectIdProvider);
  final repo = ref.watch(financialsRepositoryProvider);

  Future<List<Payout>> fetchReal() async {
    final scope = (selectedId != null && !selectedId.startsWith(demoIdPrefix))
        ? selectedId
        : null;
    try {
      return await trackedFetch(ref, () => repo.myPayouts(projectId: scope));
    } catch (_) {
      return const <Payout>[];
    }
  }

  if (SessionManager.isLoggedIn) {
    return fetchReal();
  }

  try {
    final investor = await ref.watch(currentInvestorProvider.future);
    if (investor != null) {
      return fetchReal();
    }
  } catch (_) {}
  return demoPayouts(projectId: selectedId);
});

/// Financials-tab portfolio. When a single project is selected we
/// rebuild the aggregate from that project's `investor_units` row so
/// the Capital Account / Earnings Outlook reflect the selection. When
/// "All Projects" is picked (selectedId == null) we just pass the
/// portfolio_summary view through unchanged.
final scopedPortfolioProvider = FutureProvider<PortfolioSummary>((ref) async {
  // Rebuild on auth state changes so a sign-in immediately replaces
  // the unauthenticated base with the user's real portfolio.
  ref.watch(authStateProvider);

  PortfolioSummary base;
  try {
    base = await ref.watch(portfolioSummaryProvider.future);
  } catch (_) {
    // Never fall through to demo when the user is signed in — show
    // a zero-state instead. Demo is reserved for unauthenticated.
    base = SessionManager.isLoggedIn
        ? PortfolioSummary.empty(investorName: 'Investor')
        : demoPortfolioSummary();
  }
  final selectedId = ref.watch(selectedProjectIdProvider);
  if (selectedId == null || selectedId.startsWith(demoIdPrefix)) return base;
  try {
    final iu = await ref.watch(investorAllocationProvider(selectedId).future);
    if (iu == null) {
      // Project selected but no allocation row — surface a clean
      // zero-state for that project rather than the global aggregate.
      return PortfolioSummary.empty(investorName: base.investorName);
    }
    final invested = iu.capitalInvested + iu.tokenAdvanceAmount;
    // Compute actual processed payouts for this project from the payouts
    // ledger. payoutsProvider is already scoped to selectedId, so we just
    // sum the processed non-demo rows. Do NOT use iu.totalAmountReceived —
    // that field is the investor's capital payment IN, not a distribution OUT.
    final payouts = await ref.watch(payoutsProvider.future);
    final projectPayoutsTotal = payouts
        .where((p) => p.status == 'processed' && !p.isDemo)
        .fold(0.0, (double sum, p) => sum + p.amount);
    return PortfolioSummary(
      investorName: base.investorName,
      totalInvested: invested,
      totalReceived: projectPayoutsTotal,
      pendingAmount: iu.capitalOutstanding,
      activeUnits: iu.issuedUnits,
      projectCount: 1,
      avgAnnualYieldPct: iu.annualYieldPct,
      nextPayoutAmount: 0,
      nextPayoutDate: iu.nextPayoutDate ?? base.nextPayoutDate,
      roiPercent:
          invested > 0 ? (projectPayoutsTotal / invested) * 100 : 0,
      annualReturns: 0,
    );
  } catch (_) {
    return base;
  }
});
