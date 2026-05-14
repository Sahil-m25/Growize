// Sentry crash-reporting configuration for the Growize investor app.
//
// Privacy posture (DPDP Act compliance — see decision file
// .claude/decisions/2026-05-13_sentry-reintegration.md):
//   * Events are scrubbed CLIENT-SIDE (this file) before transmit AND
//     SERVER-SIDE by Sentry's PII scrubbers (custom sensitive fields
//     configured in the project settings: pan, aadhaar, account_number,
//     account, ifsc, dob, phone, pin, pin_hash).
//   * `sendDefaultPii` is OFF — no IP, no auto-attached user identity.
//   * `attachScreenshot` and `attachViewHierarchy` are OFF — KYC and
//     bank screens could leak otherwise.
//   * The Sentry project is hosted in the EU region.
//
// Do NOT enable attachScreenshot or sendDefaultPii without a privacy
// review. The whole point of running our own scrubber on top of
// Sentry's is defense in depth.

import 'dart:async';

import 'package:sentry_flutter/sentry_flutter.dart';

/// Regex patterns for PII we never want to ship off-device.
/// Ordered so that the most specific patterns run first; the
/// generic-account-number pattern is intentionally last because it would
/// otherwise also match Aadhaar 12-digit runs.
final _patterns = <_ScrubRule>[
  _ScrubRule(
    name: 'pan',
    pattern: RegExp(r'\b[A-Z]{5}[0-9]{4}[A-Z]\b', caseSensitive: false),
    replacement: '<PAN_REDACTED>',
  ),
  _ScrubRule(
    name: 'aadhaar',
    pattern: RegExp(r'\b\d{4}[\s-]?\d{4}[\s-]?\d{4}\b'),
    replacement: '<AADHAAR_REDACTED>',
  ),
  _ScrubRule(
    name: 'ifsc',
    pattern: RegExp(r'\b[A-Z]{4}0[A-Z0-9]{6}\b'),
    replacement: '<IFSC_REDACTED>',
  ),
  _ScrubRule(
    name: 'phone_in',
    pattern: RegExp(r'\+?91[-\s]?[6-9]\d{9}'),
    replacement: '<PHONE_REDACTED>',
  ),
  _ScrubRule(
    name: 'jwt',
    pattern: RegExp(
      r'\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b',
    ),
    replacement: '<JWT_REDACTED>',
  ),
  _ScrubRule(
    name: 'bearer',
    pattern: RegExp(r'(?:Bearer|bearer)\s+[A-Za-z0-9._\-=]{8,}'),
    replacement: 'Bearer <TOKEN_REDACTED>',
  ),
  _ScrubRule(
    name: 'email',
    pattern: RegExp(
      r'\b([A-Za-z0-9._%+-])[A-Za-z0-9._%+-]*@([A-Za-z0-9.-]+\.[A-Za-z]{2,})\b',
    ),
    replacement: r'$1***@$2',
  ),
  // Generic long digit run — catches account numbers AND any other
  // numeric secret. Runs after aadhaar so 12-digit Aadhaar values
  // are already masked.
  _ScrubRule(
    name: 'long_digit_run',
    pattern: RegExp(r'\b\d{9,18}\b'),
    replacement: '<DIGITS_REDACTED>',
  ),
];

/// Apply all scrub rules to a single string. Exposed for unit testing.
String scrubText(String input) {
  var out = input;
  for (final rule in _patterns) {
    out = out.replaceAllMapped(rule.pattern, (m) {
      // Email rule has captures we want to preserve (first char + domain).
      if (rule.name == 'email') {
        return '${m.group(1)}***@${m.group(2)}';
      }
      return rule.replacement;
    });
  }
  return out;
}

/// Null-safe convenience.
String? scrubNullable(String? input) => input == null ? null : scrubText(input);

/// `beforeSend` hook for SentryFlutter.init.
///
/// Modifies the event in place (returns the same instance) so we keep the
/// crash signal but strip the PII payload. Returning `null` would drop the
/// event entirely — we don't do that, because losing a crash report is
/// worse than shipping a redacted one.
FutureOr<SentryEvent?> scrubPii(SentryEvent event, Hint hint) {
  // Message. SentryMessage is immutable but cheap to recreate.
  final message = event.message;
  if (message != null) {
    event.message = SentryMessage(
      scrubText(message.formatted),
      template: scrubNullable(message.template),
      params:
          message.params?.map((p) => p is String ? scrubText(p) : p).toList(),
    );
  }

  // Exceptions — mutate `.value` in place.
  final exceptions = event.exceptions;
  if (exceptions != null && exceptions.isNotEmpty) {
    for (final e in exceptions) {
      e.value = scrubNullable(e.value);
    }
  }

  // Breadcrumbs — mutate `.message` and `.data` in place.
  final crumbs = event.breadcrumbs;
  if (crumbs != null && crumbs.isNotEmpty) {
    for (final c in crumbs) {
      c.message = scrubNullable(c.message);
      final data = c.data;
      if (data != null) {
        for (final k in data.keys.toList()) {
          final v = data[k];
          if (v is String) data[k] = scrubText(v);
        }
      }
    }
  }

  return event;
}

class _ScrubRule {
  final String name;
  final RegExp pattern;
  final String replacement;
  const _ScrubRule({
    required this.name,
    required this.pattern,
    required this.replacement,
  });
}
