import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arl_app/core/offline/hive_cache.dart';
import 'package:arl_app/core/providers/repositories.dart';
import 'package:arl_app/features/projects/projects_provider.dart';

/// Hive key — stores `true` once the user has seen + dismissed the
/// tutorial at least once. Survives app restarts.
const String _kTutorialSeenKey = 'tutorial_seen_v1';

bool _readSeen() {
  try {
    return (hiveBox(HiveBoxes.auth).get(_kTutorialSeenKey, defaultValue: false)
            as bool?) ??
        false;
  } catch (_) {
    return false;
  }
}

Future<void> _writeSeen(bool value) async {
  try {
    await hiveBox(HiveBoxes.auth).put(_kTutorialSeenKey, value);
  } catch (_) {
    // Box not opened yet (first call too early) — ignore.
  }
}

/// Has the user EVER completed/skipped the tutorial. Persisted to Hive.
final tutorialSeenProvider = StateProvider<bool>((ref) => _readSeen());

/// Has the user dismissed the tutorial in THIS app session. In-memory
/// only — resets on every fresh launch so an investor with zero
/// allocations gets re-prompted next time.
final tutorialSessionDismissedProvider = StateProvider<bool>((ref) => false);

/// Manual-replay flag — set when the user taps "Replay Tour" so the
/// overlay opens even if their portfolio already has allocations.
/// Without this, the hasAllocations guard would silently swallow the
/// replay request.
final tutorialForceOpenProvider = StateProvider<bool>((ref) => false);

/// Computed: should the overlay render right now?
///
/// Show when:
///   - User is signed in (we have an investor row), AND
///   - User has not dismissed it in this session, AND
///   - EITHER the user explicitly tapped "Replay Tour" (force flag),
///     OR the user has never seen it AND has no allocations (the
///     overlay is empty-state hand-holding with sample numbers — once
///     real allocations exist, those sample numbers conflict with the
///     real data shown elsewhere on the same screen).
final shouldShowTutorialProvider = Provider<bool>((ref) {
  final investor = ref.watch(currentInvestorProvider).valueOrNull;
  if (investor == null) return false;

  final dismissed = ref.watch(tutorialSessionDismissedProvider);
  if (dismissed) return false;

  final force = ref.watch(tutorialForceOpenProvider);
  if (force) return true;

  final projects = ref.watch(projectsProvider).valueOrNull ?? const [];
  final hasAllocations = projects.isNotEmpty;
  // Investor already has units — sample portfolio card would clash
  // with their real numbers. Skip auto-show. Replay button still works
  // via the force flag above.
  if (hasAllocations) return false;

  final seen = ref.watch(tutorialSeenProvider);
  return !seen;
});

/// Force the tutorial to open (bound to "Replay Tour" in Profile).
/// Resets the seen + dismiss flags AND raises the force flag so the
/// hasAllocations guard in shouldShowTutorialProvider lets the overlay
/// through for investors who already have a real portfolio.
Future<void> replayTutorial(WidgetRef ref) async {
  await _writeSeen(false);
  ref.read(tutorialSeenProvider.notifier).state = false;
  ref.read(tutorialSessionDismissedProvider.notifier).state = false;
  ref.read(tutorialForceOpenProvider.notifier).state = true;
}

/// Mark the tutorial as completed/skipped. Persists + dismisses session.
Future<void> dismissTutorial(WidgetRef ref) async {
  await _writeSeen(true);
  ref.read(tutorialSeenProvider.notifier).state = true;
  ref.read(tutorialSessionDismissedProvider.notifier).state = true;
  ref.read(tutorialForceOpenProvider.notifier).state = false;
}
