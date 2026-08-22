import 'package:flutter/material.dart';
import 'dart:io';

import 'package:flutter/services.dart';
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

/// Renders the real screens with the real Eka data and writes PNGs to
/// test/goldens/.
///
/// SKIPPED BY DEFAULT. Golden comparison is font- and platform-sensitive,
/// so leaving this in the normal `flutter test` path would make CI fail on
/// any machine whose text rasterises a pixel differently. These images are
/// documentation — proof of what the stage update looks like — not a
/// regression gate. The behavioural assertions live in
/// eka_stage_timeline_test.dart, which DOES run every time.
///
/// To regenerate:
///   RENDER_SCREENSHOTS=1 flutter test test/eka_screenshot_test.dart --update-goldens

const ekaId = '6cb9fe7c-b173-4e39-a613-93bda03ca9f4';
const _labels = <String>[
  'Land Closed', 'Design & Plan Locked', 'Site Prep', 'Core Civil',
  'Procurement Locked', 'Water Source & Storage Ready', 'Power Ready',
  'Greenhouse', 'Production Systems Installed', 'Compliance Closed + Go-live',
];

/// flutter_test ships no real font, so every glyph renders as a box
/// unless we register one. rootBundle is unreliable here (the test asset
/// bundle is not always populated), so read the TTFs straight off disk.
Future<void> _loadInter() async {
  final loader = FontLoader('Inter');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    final bytes = await File('assets/fonts/Inter-$w.ttf').readAsBytes();
    loader.addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
  }
  await loader.load();

  // Icons render as empty boxes without this — the icon font lives in the
  // SDK cache, not in the app's own assets.
  final iconFont = File('${Platform.environment['FLUTTER_ROOT'] ?? '/home/claude/flutter'}'
      '/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (iconFont.existsSync()) {
    final il = FontLoader('MaterialIcons');
    il.addFont(Future<ByteData>.value(
        ByteData.sublistView(await iconFont.readAsBytes())));
    await il.load();
  }

  // The default TextStyle has no family, so also register the same face
  // under the engine's fallback names.
  for (final family in ['Roboto', 'packages/arl_app/Inter']) {
    final fb = FontLoader(family);
    final bytes = await File('assets/fonts/Inter-Regular.ttf').readAsBytes();
    fb.addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    await fb.load();
  }
}

Project _eka() => Project.fromSupabase(<String, dynamic>{
      'id': ekaId,
      'name': 'EKA LLP',
      'status': 'Open for Reservation',
      'tier': '25 L',
      'launch_year': '2026-06-12',
      'total_units': 22,
      'units_issued': 2,
      'total_ticket_size': 55000000,
    });

List<ProjectPhase> _phases({int? currentIdx, int doneUpTo = -1}) =>
    List<ProjectPhase>.generate(10, (i) => ProjectPhase(
          id: 'ph$i',
          projectId: ekaId,
          name: _labels[i],
          status: i == currentIdx
              ? 'current'
              : (i <= doneUpTo ? 'done' : 'pending'),
          sortOrder: i,
        ));

final _enabled = Platform.environment.containsKey('RENDER_SCREENSHOTS');

void main() {
  setUpAll(() async {
    if (!_enabled) return;
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadInter();
  });

  Future<void> sized(WidgetTester t) async {
    t.view.devicePixelRatio = 2.0;
    t.view.physicalSize = const Size(390 * 2, 1100 * 2);
    addTearDown(t.view.reset);
  }

  testWidgets('project detail — Eka today (all stages pending)', (t) async {
    await sized(t);
    await t.pumpWidget(ProviderScope(overrides: [
      projectByIdProvider(ekaId).overrideWith((ref) async => _eka()),
      projectPhasesProvider(ekaId).overrideWith((ref) async => _phases()),
      projectUpdatesProvider(ekaId)
          .overrideWith((ref) async => const <ProjectUpdate>[]),
      investorAllocationProvider(ekaId)
          .overrideWith((ref) async => null as InvestorUnit?),
      payoutsProvider.overrideWith((ref) async => const <Payout>[]),
      projectDocumentsProvider(ekaId)
          .overrideWith((ref) async => const <ProjectDocument>[]),
    ], child: const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: ProjectDetailScreen(projectId: ekaId))));
    await t.pumpAndSettle();
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/eka_detail_seeded.png'));
  }, skip: !_enabled);

  // The state production is in RIGHT NOW: Land Closed signed off
  // 2026-08-22, everything after it still pending.
  testWidgets('project detail — Land Closed complete (live state)', (t) async {
    await sized(t);
    await t.pumpWidget(ProviderScope(overrides: [
      projectByIdProvider(ekaId).overrideWith((ref) async => _eka()),
      projectPhasesProvider(ekaId)
          .overrideWith((ref) async => _phases(doneUpTo: 0)),
      projectUpdatesProvider(ekaId)
          .overrideWith((ref) async => const <ProjectUpdate>[]),
      investorAllocationProvider(ekaId)
          .overrideWith((ref) async => null as InvestorUnit?),
      payoutsProvider.overrideWith((ref) async => const <Payout>[]),
      projectDocumentsProvider(ekaId)
          .overrideWith((ref) async => const <ProjectDocument>[]),
    ], child: const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: ProjectDetailScreen(projectId: ekaId))));
    await t.pumpAndSettle();
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/eka_detail_land_complete.png'));
  }, skip: !_enabled);

  testWidgets('project detail — after step 5 (Land Closed current)', (t) async {
    await sized(t);
    await t.pumpWidget(ProviderScope(overrides: [
      projectByIdProvider(ekaId).overrideWith((ref) async => _eka()),
      projectPhasesProvider(ekaId)
          .overrideWith((ref) async => _phases(currentIdx: 0)),
      projectUpdatesProvider(ekaId)
          .overrideWith((ref) async => const <ProjectUpdate>[]),
      investorAllocationProvider(ekaId)
          .overrideWith((ref) async => null as InvestorUnit?),
      payoutsProvider.overrideWith((ref) async => const <Payout>[]),
      projectDocumentsProvider(ekaId)
          .overrideWith((ref) async => const <ProjectDocument>[]),
    ], child: const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: ProjectDetailScreen(projectId: ekaId))));
    await t.pumpAndSettle();
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/eka_detail_current.png'));
  }, skip: !_enabled);

  testWidgets('activity feed — the phase_update investors will receive',
      (t) async {
    await sized(t);
    // Exactly the row the migration-066 trigger produced in the
    // production smoke test on 2026-08-22.
    final n = ArlNotification.fromSupabase(<String, dynamic>{
      'id': 'n1',
      'type': 'phase_update',
      'title': 'Land Acquired!',
      'body': "EKA LLP: we will start construction next. "
          "We'll keep you posted.",
      'read_at': null,
      'created_at': '2026-08-22T10:00:00Z',
      'metadata': {
        'project_id': ekaId,
        'project_name': 'EKA LLP',
        'stage_index': 0,
        'phase_name': 'Land Closed',
        'kind': 'completed',
        'cta_route': '/projects/$ekaId',
        'cta_label': 'View Project',
      },
    });
    await t.pumpWidget(ProviderScope(overrides: [
      notificationsProvider.overrideWith((ref) async => [n]),
    ], child: const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: ActivityScreen())));
    await t.pumpAndSettle();
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/eka_activity_notification.png'));
  }, skip: !_enabled);
}
