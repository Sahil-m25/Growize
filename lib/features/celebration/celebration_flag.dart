import 'package:hive_flutter/hive_flutter.dart';

/// Persists whether the first-payout celebration overlay has been shown.
///
/// Stored in a dedicated Hive box (`celebration_cache`) so this state is
/// independent of any other feature's cache lifecycle (clearing financials
/// cache, for example, must NOT re-trigger the celebration).
///
/// Hive is initialised in `core/offline/hive_cache.dart`'s `initHive()` at
/// app start, but the box used here is opened lazily on first read to keep
/// this feature self-contained (T1) and avoid editing shared infrastructure.
abstract final class CelebrationFlag {
  static const String _boxName = 'celebration_cache';
  static const String _firstPayoutSeenKey = 'first_payout_seen';

  static Future<Box<dynamic>> _box() async {
    if (Hive.isBoxOpen(_boxName)) {
      return Hive.box<dynamic>(_boxName);
    }
    return Hive.openBox<dynamic>(_boxName);
  }

  /// True if the user has already seen (and dismissed) the first-payout
  /// celebration overlay. Defaults to `false` when no value is stored.
  static Future<bool> hasSeen() async {
    try {
      final box = await _box();
      return box.get(_firstPayoutSeenKey, defaultValue: false) == true;
    } catch (_) {
      // If Hive isn't ready for any reason, behave as if not seen — the
      // worst case is showing the celebration once on a fresh install.
      return false;
    }
  }

  /// Marks the celebration as seen. Idempotent — safe to call multiple
  /// times. Called from CelebrationScreen's "Maybe later" link and from
  /// CelebrationTrigger after the push returns.
  static Future<void> markSeen() async {
    try {
      final box = await _box();
      await box.put(_firstPayoutSeenKey, true);
    } catch (_) {
      // Swallow — failure to persist just means we may re-show once.
    }
  }

  /// Test / preview helper — wipes the flag so the next eligible session
  /// will re-trigger the overlay. Not wired in product code; left here for
  /// QA flows (e.g. invoked from a debug menu by T4).
  static Future<void> reset() async {
    try {
      final box = await _box();
      await box.delete(_firstPayoutSeenKey);
    } catch (_) {}
  }
}
