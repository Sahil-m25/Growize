import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:arl_app/core/mock/mock_data.dart' show mockTimelineEvents;
import 'package:arl_app/core/navigation/route_names.dart';
import 'package:arl_app/core/providers/repositories.dart';
import 'package:arl_app/core/utils/money.dart';
import 'package:arl_app/features/projects/projects_provider.dart';
import 'package:arl_app/features/updates/updates.dart';

/// One row on the account History timeline.
class TimelineEvent {
  final String type; // 'investment' | 'payout' | 'farm'
  final String title;
  final String subtitle;
  final DateTime date;
  final double? amount; // payout credited (₹)
  final String? utr;
  final String? route; // where tapping the row goes

  const TimelineEvent({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.date,
    this.amount,
    this.utr,
    this.route,
  });
}

/// The investor's own history, newest first, built from real records:
/// allotments (investment date), processed payouts, and farm updates for
/// the farms they hold. Only past events; nothing is invented.
final activityTimelineProvider =
    FutureProvider<List<TimelineEvent>>((ref) async {
  final now = DateTime.now();
  final events = <TimelineEvent>[];

  final projects = await ref.watch(projectsProvider.future);
  final names = {for (final p in projects) p.id: p.name};

  try {
    final units = await ref.watch(investorUnitsListProvider.future);
    for (final u in units) {
      if (u.isDemo || u.investmentDate == null) continue;
      if (u.investmentDate!.isAfter(now)) continue;
      final name = names[u.projectId] ?? 'your farm';
      final invested = u.capitalInvested + u.tokenAdvanceAmount;
      final units = u.issuedUnits == 1 ? '1 unit' : '${u.issuedUnits} units';
      events.add(TimelineEvent(
        type: 'investment',
        title: 'Invested in $name',
        subtitle: invested > 0
            ? '$units · ${Money.inr(invested, inline: true)}'
            : units,
        date: u.investmentDate!,
        route: '${RouteNames.projects}/${u.projectId}',
      ));
    }
  } catch (_) {}

  try {
    final payouts = await ref.read(financialsRepositoryProvider).myPayouts();
    for (final p in payouts) {
      if (p.isDemo || p.status != 'processed' || p.date.isAfter(now)) continue;
      events.add(TimelineEvent(
        type: 'payout',
        title: 'Payout credited',
        subtitle: p.projectName.isNotEmpty ? p.projectName : 'Payout',
        date: p.date,
        amount: p.amount,
        utr: p.utrRef,
        route: RouteNames.financials,
      ));
    }
  } catch (_) {}

  final updates = await ref.watch(allUpdatesProvider.future);
  for (final u in updates) {
    events.add(TimelineEvent(
      type: 'farm',
      title: u.title,
      subtitle: names[u.projectId] ?? 'Farm update',
      date: u.updateDate,
      route: '${RouteNames.updates}/${u.id}',
    ));
  }

  events.sort((a, b) => b.date.compareTo(a.date));
  return events;
});

/// Design-preview (signed-out) timeline from the demo mocks.
List<TimelineEvent> demoTimeline() => [
      for (final e in mockTimelineEvents)
        TimelineEvent(
          type: e.type == 'payout' ? 'payout' : 'farm',
          title: e.title,
          subtitle: e.subtitle,
          date: e.date,
          amount: e.amount,
          utr: e.utr,
        ),
    ];
