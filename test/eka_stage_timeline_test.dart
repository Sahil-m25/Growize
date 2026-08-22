import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arl_app/features/activity/activity_provider.dart';
import 'package:arl_app/features/activity/activity_screen.dart';
import 'package:arl_app/features/activity/models/notification.dart';
import 'package:arl_app/features/documents/documents_provider.dart';
import 'package:arl_app/features/documents/models/project_document.dart';
import 'package:arl_app/features/financials/financials_provider.dart';
import 'package:arl_app/features/financials/models/payout.dart';
import 'package:arl_app/features/projects/models/investor_unit.dart';
import 'package:arl_app/features/projects/models/project.dart';
import 'package:arl_app/features/projects/models/project_phase.dart';
import 'package:arl_app/features/projects/models/project_update.dart';
import 'package:arl_app/features/projects/project_detail_screen.dart';
import 'package:arl_app/features/projects/projects_provider.dart';

/// End-to-end UI check for the Eka stage update (migration 066).
///
/// Data below is copied from PRODUCTION as verified 2026-08-22 against
/// project ref oynfhdqizebvgmaoiuax: EKA LLP, 10 project_phases rows,
/// all `pending`, target stage 0 (Land Closed).
///
/// The point of these tests is the divergence in `_stageIndexFor`.
/// Before migration 066 the stage came from `progressPercent`
/// (monthsElapsed / totalMonths), so the timeline crept forward on the
/// calendar no matter what ops recorded. Now real `project_phases` rows
/// win. `heuristic would disagree` is the test that actually proves the
/// fix bites — it is the case that used to be wrong.

const ekaId = '6cb9fe7c-b173-4e39-a613-93bda03ca9f4';

const _labels = <String>[
  'Land Closed',
  'Design & Plan Locked',
  'Site Prep',
  'Core Civil',
  'Procurement Locked',
  'Water Source & Storage Ready',
  'Power Ready',
  'Greenhouse',
  'Production Systems Installed',
  'Compliance Closed + Go-live',
];

Project _eka({String launchYear = '2026-06-12'}) =>
    Project.fromSupabase(<String, dynamic>{
      'id': ekaId,
      'name': 'EKA LLP',
      'status': 'Open for Reservation',
      'tier': '25 L',
      'launch_year': launchYear,
      'total_units': 22,
      'units_issued': 2,
      'total_ticket_size': 55000000,
    });

/// The 10 rows exactly as seeded in prod. [currentIdx] marks one row
/// `current`; null leaves every row `pending`, which is the state the
/// database is in right now (step 5 not yet run).
List<ProjectPhase> _phases({int? currentIdx, int doneUpTo = -1}) {
  return List<ProjectPhase>.generate(_labels.length, (i) {
    final status = i == currentIdx
        ? 'current'
        : (i <= doneUpTo ? 'done' : 'pending');
    return ProjectPhase(
      id: 'ph$i',
      projectId: ekaId,
      name: _labels[i],
      status: status,
      sortOrder: i,
    );
  });
}

Widget _detailScreen(List<ProjectPhase> phases, {Project? project}) {
  return ProviderScope(
    overrides: [
      projectByIdProvider(ekaId).overrideWith((ref) async => project ?? _eka()),
      projectPhasesProvider(ekaId).overrideWith((ref) async => phases),
      projectUpdatesProvider(ekaId)
          .overrideWith((ref) async => const <ProjectUpdate>[]),
      investorAllocationProvider(ekaId)
          .overrideWith((ref) async => null as InvestorUnit?),
      payoutsProvider.overrideWith((ref) async => const <Payout>[]),
      projectDocumentsProvider(ekaId)
          .overrideWith((ref) async => const <ProjectDocument>[]),
    ],
    child: const MaterialApp(
      home: ProjectDetailScreen(projectId: ekaId),
    ),
  );
}

void main() {
  group('Eka project detail — stage timeline', () {
    testWidgets('renders Land Closed as stage 1/10 from the seeded rows',
        (tester) async {
      await tester.pumpWidget(_detailScreen(_phases()));
      await tester.pumpAndSettle();

      // The "Current Phase — <stage>" header was removed 2026-08-22; the
      // compact node label, its in-progress caption and the counter pill
      // are what remain on the card face.
      expect(find.text('Land'), findsOneWidget);
      expect(find.text('(in progress)'), findsOneWidget);
      expect(find.text('1/10'), findsOneWidget);
    });

    testWidgets('a row marked current wins — the post-step-5 state',
        (tester) async {
      await tester.pumpWidget(_detailScreen(_phases(currentIdx: 0)));
      await tester.pumpAndSettle();

      expect(find.text('Land'), findsOneWidget);
      expect(find.text('1/10'), findsOneWidget);
    });

    testWidgets('advancing to Site Prep moves the pill to 3/10',
        (tester) async {
      await tester
          .pumpWidget(_detailScreen(_phases(currentIdx: 2, doneUpTo: 1)));
      await tester.pumpAndSettle();

      expect(find.text('Site'), findsOneWidget);
      expect(find.text('3/10'), findsOneWidget);
    });

    testWidgets('the Current Phase header bar and tier badge are gone',
        (tester) async {
      await tester.pumpWidget(_detailScreen(_phases()));
      await tester.pumpAndSettle();

      // Removed 2026-08-22 per design feedback. `Premium` was worse than
      // redundant: _tierFor defaulted every project to it, because prod
      // tiers are ticket-size strings like "25 L".
      expect(find.textContaining('Current Phase', findRichText: true),
          findsNothing);
      expect(find.text('Premium'), findsNothing);
      expect(find.byIcon(Icons.eco_outlined), findsNothing);
      expect(find.byIcon(Icons.workspace_premium_outlined), findsNothing);
      // ...but the counter survives.
      expect(find.text('1/10'), findsOneWidget);
    });

    testWidgets('REGRESSION: tracked stages never get invented dates',
        (tester) async {
      // 2026-08-22: Land Closed was signed off with a null phase_date and
      // the timeline captioned it "18 Jul" — a date nobody had entered.
      // _phaseDatesFor had guarded its synthetic block on "any row HAS a
      // date" rather than "any real row EXISTS", so undated real stages
      // fell through to the demo date generator. A done stage with no
      // recorded date must render no date at all.
      final done = _phases(doneUpTo: 0);
      await tester.pumpWidget(_detailScreen(done));
      await tester.pumpAndSettle();

      expect(find.text('Land'), findsOneWidget);
      expect(find.text('2/10'), findsOneWidget,
          reason: 'stage 0 done -> the timeline sits on stage 1');
      // The node caption format is "d MMM" (e.g. "18 Jul"). Match that
      // shape specifically — the Contract Progress card legitimately
      // renders "Jun 2026" / "Jun 2031" and must not trip this.
      final nodeDate = RegExp(r'^\d{1,2} [A-Z][a-z]{2}$');
      final captions = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .whereType<String>()
          .where(nodeDate.hasMatch)
          .toList();
      expect(captions, isEmpty,
          reason: 'undated stages must render no date caption, but found '
              '$captions — that is the synthetic generator leaking');
    });

    testWidgets('REGRESSION: real rows beat the calendar heuristic',
        (tester) async {
      // A project launched 40 months ago. The old code did
      // round(40/60 * 100 / 100 * 9) = stage 6 (Power Ready) purely from
      // elapsed time. The seeded rows say Land Closed. Real data must win.
      final old = _eka(launchYear: '2023-04-12');
      await tester.pumpWidget(_detailScreen(_phases(), project: old));
      await tester.pumpAndSettle();

      expect(find.text('1/10'), findsOneWidget,
          reason: 'phase rows must override the elapsed-months heuristic');
      expect(find.text('7/10'), findsNothing);
    });

    testWidgets('no phase rows still falls back to the heuristic',
        (tester) async {
      // Nothing seeded -> old behaviour preserved for projects that have
      // never had stage rows written.
      final old = _eka(launchYear: '2023-04-12');
      await tester.pumpWidget(
          _detailScreen(const <ProjectPhase>[], project: old));
      await tester.pumpAndSettle();

      expect(find.text('1/10'), findsNothing,
          reason: 'without rows the heuristic should still advance');
    });
  });

  group('Activity feed — phase_update notification', () {
    // The exact row the migration-066 trigger produces, captured from the
    // production smoke test on 2026-08-22.
    final ekaNotification = ArlNotification.fromSupabase(<String, dynamic>{
      'id': 'n1',
      'type': 'phase_update',
      'title': 'Stage update: Land Closed',
      'body': 'EKA LLP has moved to Land Closed.',
      'read_at': null,
      'created_at': '2026-08-22T10:00:00Z',
      'metadata': {
        'project_id': ekaId,
        'project_name': 'EKA LLP',
        'stage_index': 0,
        'phase_name': 'Land Closed',
        'cta_route': '/projects/$ekaId',
        'cta_label': 'View Project',
      },
    });

    test('maps phase_update to the milestone display tint', () {
      expect(ekaNotification.displayType, 'milestone');
      expect(ekaNotification.isRead, isFalse);
      expect(ekaNotification.metadata!['cta_route'], '/projects/$ekaId');
    });

    testWidgets('renders the card with its title, body and CTA',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            notificationsProvider
                .overrideWith((ref) async => [ekaNotification]),
          ],
          child: const MaterialApp(home: ActivityScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Stage update: Land Closed'), findsOneWidget);
      expect(find.text('EKA LLP has moved to Land Closed.'), findsOneWidget);
      expect(find.text('View Project'), findsOneWidget);
      expect(find.byIcon(Icons.flag_outlined), findsOneWidget);
    });
  });
}
