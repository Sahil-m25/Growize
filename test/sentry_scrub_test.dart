import 'package:flutter_test/flutter_test.dart';
import 'package:arl_app/core/observability/sentry_config.dart';

void main() {
  group('scrubText', () {
    test('redacts PAN', () {
      final out = scrubText('User ABCDE1234F failed step 2.');
      expect(out, contains('<PAN_REDACTED>'));
      expect(out, isNot(contains('ABCDE1234F')));
    });

    test('redacts PAN regardless of case', () {
      final out = scrubText('pan abcde1234f trailing');
      expect(out, contains('<PAN_REDACTED>'));
    });

    test('redacts 12-digit Aadhaar — plain', () {
      final out = scrubText('aadhaar=123412341234');
      expect(out, contains('<AADHAAR_REDACTED>'));
      expect(out, isNot(contains('123412341234')));
    });

    test('redacts 12-digit Aadhaar — space-separated', () {
      final out = scrubText('aadhaar 1234 5678 9012 end');
      expect(out, contains('<AADHAAR_REDACTED>'));
    });

    test('redacts 12-digit Aadhaar — hyphen-separated', () {
      final out = scrubText('1234-5678-9012');
      expect(out, contains('<AADHAAR_REDACTED>'));
    });

    test('redacts IFSC', () {
      final out = scrubText('IFSC HDFC0001234 bank ok');
      expect(out, contains('<IFSC_REDACTED>'));
      expect(out, isNot(contains('HDFC0001234')));
    });

    test('redacts long digit run (account number)', () {
      final out = scrubText('account=123456789012 ok');
      // Aadhaar pattern matches 12-digit runs first, so this redacts as AADHAAR.
      // Either redaction is acceptable — the goal is the digits are gone.
      expect(out, isNot(contains('123456789012')));
      expect(out,
          anyOf(contains('<AADHAAR_REDACTED>'), contains('<DIGITS_REDACTED>')));
    });

    test('redacts 10-digit account number (non-aadhaar length)', () {
      final out = scrubText('acct 1234567890 done');
      expect(out, contains('<DIGITS_REDACTED>'));
      expect(out, isNot(contains('1234567890')));
    });

    test('redacts Indian phone with +91', () {
      final out = scrubText('contact +91 9876543210 today');
      expect(out, contains('<PHONE_REDACTED>'));
      expect(out, isNot(contains('9876543210')));
    });

    test('redacts email local part but keeps domain', () {
      final out = scrubText('user alice@example.com asked');
      expect(out, contains('@example.com'));
      expect(out, isNot(contains('alice@')));
      expect(out, contains('***@example.com'));
    });

    test('redacts JWT-looking token', () {
      final out = scrubText(
          'auth=eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.SflKxwRJSMeKKF2QT4f');
      expect(out, contains('<JWT_REDACTED>'));
    });

    test('redacts Bearer tokens', () {
      final out = scrubText('Authorization: Bearer sk_live_abc123XYZpassword');
      expect(out, contains('<TOKEN_REDACTED>'));
      expect(out, isNot(contains('sk_live_abc123XYZpassword')));
    });

    test('leaves benign strings alone', () {
      final out = scrubText('Could not save: TypeError on row 4');
      expect(out, equals('Could not save: TypeError on row 4'));
    });

    test('combines multiple patterns in one string', () {
      final out = scrubText(
          'investor ABCDE1234F (alice@bank.co) phone +91 9876543210 aadhaar 1234 5678 9012');
      expect(out, contains('<PAN_REDACTED>'));
      expect(out, contains('<PHONE_REDACTED>'));
      expect(out, contains('<AADHAAR_REDACTED>'));
      expect(out, contains('@bank.co'));
      expect(out, isNot(contains('ABCDE1234F')));
      expect(out, isNot(contains('9876543210')));
    });
  });

  group('scrubNullable', () {
    test('passes null through', () {
      expect(scrubNullable(null), isNull);
    });

    test('redacts non-null', () {
      expect(scrubNullable('PAN ABCDE1234F'), contains('<PAN_REDACTED>'));
    });
  });
}
