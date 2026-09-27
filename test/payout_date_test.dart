import 'package:flutter_test/flutter_test.dart';
import 'package:arl_app/features/home/investor_terms.dart';

void main() {
  test('first payout: 10th of the 7th month, counting the start month', () {
    expect(firstPayoutDate(DateTime(2026, 9, 26)), DateTime(2027, 3, 10));
    expect(firstPayoutDate(DateTime(2026, 1, 1)), DateTime(2026, 7, 10));
    expect(firstPayoutDate(DateTime(2026, 7, 31)), DateTime(2027, 1, 10));
  });
}
