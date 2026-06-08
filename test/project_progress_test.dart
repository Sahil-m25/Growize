import 'package:flutter_test/flutter_test.dart';
import 'package:arl_app/features/projects/models/project.dart';

/// Guards the home "Contract Progress" calculation.
///
/// Regression: `projectsProvider` used to overwrite `progressPercent`
/// with a phase-completion ratio (0% for projects with no phase rows),
/// which decoupled the bar/percentage from the "Month X of Y" label.
/// Progress must be derived from elapsed-vs-total contract months in
/// `Project.fromSupabase`, so the percentage, the bar fill
/// (`progressPercent / 100`), and the month label all stay in sync.

/// Builds a launch date that is exactly [k] whole months before "now",
/// using the same year*12 + month decomposition the model relies on so
/// the assertions are stable regardless of the day of the month the
/// test runs on.
DateTime _monthsAgo(int k) {
  final now = DateTime.now();
  final totalMonths = now.year * 12 + (now.month - 1) - k;
  final year = totalMonths ~/ 12;
  final month = totalMonths % 12 + 1;
  return DateTime(year, month, 1);
}

Project _project({String? launchYear, String status = 'Operational'}) {
  return Project.fromSupabase(<String, dynamic>{
    'id': 'p1',
    'name': 'Test LLP',
    'status': status,
    'launch_year': launchYear,
    'total_units': 10,
    'total_ticket_size': 100000,
  });
}

void main() {
  group('Project.fromSupabase — contract progress', () {
    test('assumes a 60-month (5-year) contract', () {
      final p = _project(launchYear: _monthsAgo(0).toIso8601String());
      expect(p.totalMonths, 60);
    });

    test('9 months in => 15% (matches design spec Month 9 of 60)', () {
      final p = _project(launchYear: _monthsAgo(9).toIso8601String());
      expect(p.monthOfContract, 9);
      expect(p.progressPercent.round(), 15);
    });

    test('27 months in => 45% (matches design spec Month 27 of 60)', () {
      final p = _project(launchYear: _monthsAgo(27).toIso8601String());
      expect(p.monthOfContract, 27);
      expect(p.progressPercent.round(), 45);
    });

    test('percentage equals monthOfContract / totalMonths * 100', () {
      final p = _project(launchYear: _monthsAgo(12).toIso8601String());
      final expected = p.monthOfContract / p.totalMonths * 100;
      expect(p.progressPercent, closeTo(expected, 0.001));
    });

    test('never exceeds 100% past the contract term', () {
      final p = _project(launchYear: _monthsAgo(75).toIso8601String());
      expect(p.progressPercent, lessThanOrEqualTo(100));
      expect(p.monthOfContract, lessThanOrEqualTo(p.totalMonths));
    });

    test('null launch_year stays in range and does not throw', () {
      final p = _project(launchYear: null);
      expect(p.totalMonths, 60);
      expect(p.progressPercent, inInclusiveRange(0, 100));
    });
  });
}
