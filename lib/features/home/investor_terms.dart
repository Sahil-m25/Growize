import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:arl_app/features/projects/models/investor_unit.dart';
import 'package:arl_app/features/projects/projects_provider.dart';

/// First payout falls on the 10th day of the 7th month of the investor's
/// term, counting the month they invested (paid in full) as month 1.
/// Invested 26 Sep 2026 -> months Sep..Mar -> first payout 10 Mar 2027.
DateTime firstPayoutDate(DateTime termStart) =>
    DateTime(termStart.year, termStart.month + 6, 10);

class NextPayoutInfo {
  final DateTime date;
  final String projectName;
  final bool isFirst;
  const NextPayoutInfo(this.date, this.projectName, {this.isFirst = true});
}

/// The next scheduled payout derived from each project's term start, for
/// the selected project (or all). Only terms that have started (paid in
/// full) count, and only dates still ahead. A real scheduled payout from
/// the ledger, when present, takes precedence in the UI.
final nextPayoutInfoProvider = FutureProvider<NextPayoutInfo?>((ref) async {
  final projects = await ref.watch(projectsProvider.future);
  final units = await ref.watch(investorUnitsListProvider.future);
  final selectedId = ref.watch(selectedProjectIdProvider);
  final held = {for (final u in units) u.projectId};
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  NextPayoutInfo? best;
  for (final p in projects) {
    if (p.isDemo || !p.termStarted || !held.contains(p.id)) continue;
    if (selectedId != null && p.id != selectedId) continue;
    final d = firstPayoutDate(p.startDate);
    if (d.isBefore(today)) continue;
    if (best == null || d.isBefore(best.date)) {
      best = NextPayoutInfo(d, p.name);
    }
  }
  return best;
});

/// Expected annual return: capital-weighted average of each allotment's
/// agreed yield (Zoho "Annual Rental Yield"), for the selected project or
/// all. Null when no allotment has a yield set.
double? expectedAnnualRoi(List<InvestorUnit> units, {String? projectId}) {
  double weight = 0, sum = 0;
  for (final u in units) {
    if (u.isDemo) continue;
    if (projectId != null && u.projectId != projectId) continue;
    if (u.annualYieldPct <= 0) continue;
    final w = u.capitalInvested > 0 ? u.capitalInvested : 1.0;
    weight += w;
    sum += u.annualYieldPct * w;
  }
  return weight > 0 ? sum / weight : null;
}

final expectedRoiProvider = FutureProvider<double?>((ref) async {
  final units = await ref.watch(investorUnitsListProvider.future);
  final selectedId = ref.watch(selectedProjectIdProvider);
  return expectedAnnualRoi(units, projectId: selectedId);
});

/// "20%" / "22.5%" — no trailing ".0".
String formatPct(double v) =>
    v == v.roundToDouble() ? '${v.toStringAsFixed(0)}%' : '${v.toStringAsFixed(1)}%';
