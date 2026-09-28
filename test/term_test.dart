import 'package:flutter_test/flutter_test.dart';
import 'package:arl_app/features/projects/models/project.dart';
import 'package:arl_app/features/projects/models/investor_unit.dart';
import 'package:arl_app/features/projects/projects_provider.dart';

Project proj() => Project(id: 'p', name: 'EKA LLP', cropType: '', location: '', status: 'active',
  startDate: DateTime(2026, 6, 12), endDate: DateTime(2031, 6, 12), totalUnits: 22, investedAmount: 0,
  progressPercent: 5, monthOfContract: 3, totalMonths: 60, colorHex: '#3C5152', initials: 'EL',
  nextPayoutAmount: 0, nextPayoutDate: null, cropEmoji: '');

InvestorUnit unit({double inv = 2500000, double rec = 2500000, double recv = 0, double out = 0, DateTime? d}) =>
  InvestorUnit(id: 'u', projectId: 'p', issuedUnits: 1, reservedUnits: 0, unitPrice: inv, capitalInvested: inv,
    capitalOutstanding: out, capitalReturns: 0, totalAmountReceivable: recv, totalAmountReceived: rec,
    tokenAdvanceAmount: 0, annualYieldPct: 0, allocationStatus: 'Issued', customerStatus: 'Active', investmentDate: d);

void main() {
  final now = DateTime.now();
  test('paid in full: term from investment date', () {
    final start = DateTime(now.year, now.month - 3, now.day);
    final p = personaliseTerm(proj(), [unit(d: start)]);
    expect(p.termStarted, true);
    expect(p.monthOfContract, 4);          // 3 full months elapsed -> month 4
    expect(p.startDate, start);
    expect(p.endDate, DateTime(start.year, start.month + 60, start.day));
    expect(p.progressPercent, closeTo(5, 0.2)); // day-precise: ~92 of 1826 days
    expect(p.progressPercent.round(), 5);
  });
  test('invested today -> month 1, 0%', () {
    final p = personaliseTerm(proj(), [unit(d: DateTime(now.year, now.month, now.day))]);
    expect(p.monthOfContract, 1); expect(p.progressPercent, 0);
  });
  test('part paid: not started, amount due', () {
    final p = personaliseTerm(proj(), [unit(rec: 1000000, recv: 1500000, d: DateTime(2026, 9, 1))]);
    expect(p.termStarted, false); expect(p.amountToComplete, 1500000);
    expect(p.monthOfContract, 0); expect(p.progressPercent, 0);
  });
  test('only invested vs received known', () {
    final p = personaliseTerm(proj(), [unit(rec: 500000, d: DateTime(2026, 9, 1))]);
    expect(p.termStarted, false); expect(p.amountToComplete, 2000000);
  });
  test('no payment figures at all -> not nagged', () {
    final p = personaliseTerm(proj(), [unit(rec: 0, d: DateTime(2026, 9, 1))]);
    expect(p.termStarted, true);
  });
  test('no units -> unchanged farm timeline', () {
    final p = personaliseTerm(proj(), []);
    expect(p.monthOfContract, 3);
  });
}
