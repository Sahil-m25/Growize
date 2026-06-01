import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:arl_app/core/navigation/route_names.dart';
import 'package:arl_app/features/onboarding/tour_keys.dart';

/// Persisted "tour seen" flag. Survives app reinstalls on iOS (Keychain
/// is preserved across reinstalls) and is encrypted at rest on Android.
const String _kTourSeenKey = 'arl_tour_seen_v2';

const FlutterSecureStorage _storage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);

/// Where the label bubble sits relative to its target cutout. The arrow
/// is then drawn from the bubble's near edge into the cutout.
enum TourArrowSide { above, below, left, right, center }

/// A single beat of the tour.
///
/// Each step optionally targets a real widget on a given [route]. The
/// overlay navigates there via GoRouter, waits for the widget to mount,
/// then paints a cutout + arrow over the target. Steps with a null
/// [targetKey] render a centered bubble instead (used for the opener
/// and closer).
class TourStep {
  /// The route the target lives on. Tour controller calls `context.go`
  /// (or `context.push` for stacked routes) before showing the step.
  final String route;

  /// Whether [route] should be pushed onto the stack instead of
  /// replacing the active tab. Used for routes like Profile / Support
  /// that are part of the ShellRoute but feel like detail pages.
  final bool pushRoute;

  /// The widget to point at. Null means "centered welcome bubble".
  final GlobalKey? targetKey;

  /// Hint for where to place the bubble. The overlay still adjusts if
  /// the preferred side would clip off-screen.
  final TourArrowSide arrowSide;

  /// Short title — read at a glance.
  final String title;

  /// One-or-two-sentence description in the friend voice.
  final String body;

  /// Inflated padding around the target's rect when painting the
  /// cutout. Default works for most controls; set higher for cards.
  final double cutoutPadding;

  const TourStep({
    required this.route,
    required this.title,
    required this.body,
    this.targetKey,
    this.arrowSide = TourArrowSide.below,
    this.pushRoute = false,
    this.cutoutPadding = 8,
  });
}

/// The full ordered tour. 20 steps; covers every primary screen plus
/// the most useful function on each.
const List<TourStep> kTourSteps = [
  // ── Opener ──────────────────────────────────────────────────────────
  TourStep(
    route: RouteNames.home,
    title: 'Welcome to Growize',
    body:
        "Quick 60-second tour. We'll point at things as we go — tap anywhere to advance, or Skip to bail out.",
    arrowSide: TourArrowSide.center,
  ),

  // ── Home top chrome ─────────────────────────────────────────────────
  TourStep(
    route: RouteNames.home,
    title: 'Two ways around',
    body:
        'The bottom bar switches between Home, Projects, Financials, and Explore. Notifications and your profile sit up top. That\'s the whole map.',
    arrowSide: TourArrowSide.center,
  ),
  TourStep(
    route: RouteNames.home,
    title: 'Notifications',
    body:
        "Your bell glows gold when there's something new — a payout, a phase update, a fresh document.",
    targetKey: null, // Overridden in tourSteps() resolver below.
    arrowSide: TourArrowSide.below,
  ),
  TourStep(
    route: RouteNames.home,
    title: 'Your profile',
    body:
        'Tap your avatar for KYC, bank, security, and to replay this tour anytime.',
    targetKey: null,
    arrowSide: TourArrowSide.below,
  ),

  // ── Home body ───────────────────────────────────────────────────────
  TourStep(
    route: RouteNames.home,
    title: 'Portfolio at a glance',
    body:
        "Total value, what you invested, what you've earned. The LIVE dot means we're syncing in real time — tap the eye to hide the numbers.",
    targetKey: null,
    arrowSide: TourArrowSide.below,
    cutoutPadding: 4,
  ),
  TourStep(
    route: RouteNames.home,
    title: 'Contract progress',
    body:
        'A slim bar for each project you own units in. Pending projects flag themselves in earth-red until payment clears.',
    targetKey: null,
    arrowSide: TourArrowSide.above,
    cutoutPadding: 4,
  ),
  TourStep(
    route: RouteNames.home,
    title: 'Active units & next payout',
    body:
        'How many units are earning, and when the next rupee lands. Tap either tile to dive deeper.',
    targetKey: null,
    arrowSide: TourArrowSide.above,
  ),

  // ── Nav to Projects ─────────────────────────────────────────────────
  TourStep(
    route: RouteNames.home,
    title: 'Projects tab',
    body:
        "Every LLP you've invested in, in one grid. Let's hop over.",
    targetKey: null,
    arrowSide: TourArrowSide.above,
  ),

  // ── Projects list ───────────────────────────────────────────────────
  TourStep(
    route: RouteNames.projects,
    title: 'Your portfolio',
    body:
        'Count, units, and total invested across every project. A clean ledger of what you own.',
    targetKey: null,
    arrowSide: TourArrowSide.below,
  ),
  TourStep(
    route: RouteNames.projects,
    title: 'Project tiles',
    body:
        'Tap a tile for the hero photo, your investment, the 10-stage phase timeline, action tiles, and recent payouts.',
    targetKey: null,
    arrowSide: TourArrowSide.above,
    cutoutPadding: 4,
  ),

  // ── Nav to Financials ───────────────────────────────────────────────
  TourStep(
    route: RouteNames.projects,
    title: 'Financials tab',
    body: 'Your full payout ledger — total earned since inception, this FY, and every credited transfer.',
    targetKey: null,
    arrowSide: TourArrowSide.above,
  ),
  TourStep(
    route: RouteNames.financials,
    title: 'Payouts',
    body:
        'Your full payout ledger — every amount credited, UTR references, and FY totals. Filter by project from the pill on the right.',
    targetKey: null,
    arrowSide: TourArrowSide.below,
  ),

  // ── Nav to Explore ──────────────────────────────────────────────────
  TourStep(
    route: RouteNames.financials,
    title: 'Explore tab',
    body: 'Upcoming offerings before they go live. The marketplace.',
    targetKey: null,
    arrowSide: TourArrowSide.above,
  ),
  TourStep(
    route: RouteNames.explore,
    title: 'Filter & browse',
    body:
        "All, Open for reservation, Coming soon, Closed. Tap any tile for the marketplace card with units available and expected return.",
    targetKey: null,
    arrowSide: TourArrowSide.below,
  ),
  TourStep(
    route: RouteNames.explore,
    title: 'Open in Maps & Share',
    body:
        "On any explore detail, an Open-in-Maps pill jumps you to the location; Share generates a clean preview card for WhatsApp.",
    targetKey: null,
    arrowSide: TourArrowSide.center,
  ),

  // ── Profile + Security ──────────────────────────────────────────────
  TourStep(
    route: RouteNames.profile,
    pushRoute: true,
    title: 'Security',
    body:
        'Biometric, PIN, and device controls. Lock the app behind your face or fingerprint in one tap.',
    targetKey: null,
    arrowSide: TourArrowSide.above,
  ),
  TourStep(
    route: RouteNames.profile,
    pushRoute: true,
    title: 'Replay this tour',
    body: 'Forgot something? The tour replays from right here, anytime.',
    targetKey: null,
    arrowSide: TourArrowSide.above,
  ),

  // ── Support ─────────────────────────────────────────────────────────
  TourStep(
    route: RouteNames.support,
    pushRoute: true,
    title: 'WhatsApp Tech & RM',
    body:
        'Two shortcuts — Tech for app issues, RM for account and payout questions. Every chat opens a tracked ticket.',
    targetKey: null,
    arrowSide: TourArrowSide.below,
  ),

  // ── Documents (via top-level route) ─────────────────────────────────
  TourStep(
    route: RouteNames.documents,
    pushRoute: true,
    title: 'Documents vault',
    body:
        "Agreements, audits, insurance, statements. Everything opens in-app — nothing leaves your session. Locked docs unlock once KYC clears.",
    targetKey: null,
    arrowSide: TourArrowSide.center,
  ),

  // ── Activity ────────────────────────────────────────────────────────
  TourStep(
    route: RouteNames.activity,
    pushRoute: true,
    title: 'Activity timeline',
    body:
        'Every payout, phase change, and announcement, grouped by month. Toggle between Notifications and History.',
    targetKey: null,
    arrowSide: TourArrowSide.center,
  ),

  // ── Closer ──────────────────────────────────────────────────────────
  TourStep(
    route: RouteNames.home,
    title: "You're set",
    body:
        "That's the tour. Replay it anytime from Profile. We're glad you're here.",
    arrowSide: TourArrowSide.center,
  ),
];

/// Build the live step list with the right GlobalKey targets wired in.
/// Done as a function rather than a const list because `TourKeys.*` are
/// runtime GlobalKey instances.
List<TourStep> tourSteps() {
  // Build a parallel list with the same content but real targetKeys.
  return [
    kTourSteps[0], // welcome
    kTourSteps[1], // logo (no target)
    TourStep(
      route: kTourSteps[2].route,
      title: kTourSteps[2].title,
      body: kTourSteps[2].body,
      targetKey: TourKeys.notificationBell,
      arrowSide: kTourSteps[2].arrowSide,
    ),
    TourStep(
      route: kTourSteps[3].route,
      title: kTourSteps[3].title,
      body: kTourSteps[3].body,
      targetKey: TourKeys.profileAvatar,
      arrowSide: kTourSteps[3].arrowSide,
    ),
    TourStep(
      route: kTourSteps[4].route,
      title: kTourSteps[4].title,
      body: kTourSteps[4].body,
      targetKey: TourKeys.portfolioCard,
      arrowSide: kTourSteps[4].arrowSide,
      cutoutPadding: kTourSteps[4].cutoutPadding,
    ),
    TourStep(
      route: kTourSteps[5].route,
      title: kTourSteps[5].title,
      body: kTourSteps[5].body,
      targetKey: TourKeys.projectProgressCard,
      arrowSide: kTourSteps[5].arrowSide,
      cutoutPadding: kTourSteps[5].cutoutPadding,
    ),
    TourStep(
      route: kTourSteps[6].route,
      title: kTourSteps[6].title,
      body: kTourSteps[6].body,
      targetKey: TourKeys.quickStatsRow,
      arrowSide: kTourSteps[6].arrowSide,
    ),
    TourStep(
      route: kTourSteps[7].route,
      title: kTourSteps[7].title,
      body: kTourSteps[7].body,
      targetKey: TourKeys.bottomNavProjects,
      arrowSide: kTourSteps[7].arrowSide,
    ),
    TourStep(
      route: kTourSteps[8].route,
      title: kTourSteps[8].title,
      body: kTourSteps[8].body,
      targetKey: TourKeys.projectsHeader,
      arrowSide: kTourSteps[8].arrowSide,
    ),
    TourStep(
      route: kTourSteps[9].route,
      title: kTourSteps[9].title,
      body: kTourSteps[9].body,
      targetKey: TourKeys.projectsGrid,
      arrowSide: kTourSteps[9].arrowSide,
      cutoutPadding: kTourSteps[9].cutoutPadding,
    ),
    TourStep(
      route: kTourSteps[10].route,
      title: kTourSteps[10].title,
      body: kTourSteps[10].body,
      targetKey: TourKeys.bottomNavFinancials,
      arrowSide: kTourSteps[10].arrowSide,
    ),
    TourStep(
      route: kTourSteps[11].route,
      title: kTourSteps[11].title,
      body: kTourSteps[11].body,
      targetKey: TourKeys.financialsHeader,
      arrowSide: kTourSteps[11].arrowSide,
    ),
    TourStep(
      route: kTourSteps[12].route,
      title: kTourSteps[12].title,
      body: kTourSteps[12].body,
      targetKey: TourKeys.bottomNavExplore,
      arrowSide: kTourSteps[12].arrowSide,
    ),
    TourStep(
      route: kTourSteps[13].route,
      title: kTourSteps[13].title,
      body: kTourSteps[13].body,
      targetKey: TourKeys.exploreFilters,
      arrowSide: kTourSteps[13].arrowSide,
    ),
    kTourSteps[14], // open in maps - centered note
    // Security step is mobile-only (biometric / PIN). Skip on web.
    if (!kIsWeb)
      TourStep(
        route: kTourSteps[15].route,
        pushRoute: kTourSteps[15].pushRoute,
        title: kTourSteps[15].title,
        body: kTourSteps[15].body,
        targetKey: TourKeys.profileSecurityTile,
        arrowSide: kTourSteps[15].arrowSide,
      ),
    TourStep(
      route: kTourSteps[16].route,
      pushRoute: kTourSteps[16].pushRoute,
      title: kTourSteps[16].title,
      body: kTourSteps[16].body,
      targetKey: TourKeys.profileReplayTour,
      arrowSide: kTourSteps[16].arrowSide,
    ),
    TourStep(
      route: kTourSteps[17].route,
      pushRoute: kTourSteps[17].pushRoute,
      title: kTourSteps[17].title,
      body: kTourSteps[17].body,
      targetKey: TourKeys.supportWhatsappTech,
      arrowSide: kTourSteps[17].arrowSide,
    ),
    kTourSteps[18], // documents - centered
    kTourSteps[19], // activity - centered
    kTourSteps[20], // closer
  ];
}

// ── State ──────────────────────────────────────────────────────────────

/// In-memory mirror of the persisted "seen" flag. Kept around so other
/// providers / widgets can read it synchronously, but it is no longer
/// the source of truth for the auto-start gate — see
/// [tourShouldAutoStartProvider] below.
///
/// On boot this defaults to `false`; [_loadSeenFlag] flips it to true
/// once secure storage has been read. The gate provider does NOT rely
/// on this default value (it would race auto-start before the storage
/// read returns), so the lag here is safe.
final tourSeenProvider = StateProvider<bool>((ref) {
  unawaited(_loadSeenFlag(ref));
  return false;
});

Future<void> _loadSeenFlag(Ref ref) async {
  try {
    final raw = await _storage.read(key: _kTourSeenKey);
    if (raw == 'true') {
      ref.read(tourSeenProvider.notifier).state = true;
    }
  } catch (_) {
    // Storage unavailable (e.g. unit tests) — fall back to "unseen" so
    // the tour can still run if asked.
  }
}

/// Whether the tour is currently being displayed. The overlay reads
/// this and renders/hides itself.
final tourActiveProvider = StateProvider<bool>((ref) => false);

/// Current step index. `kTourSteps.length` means "tour finished —
/// dismiss".
final tourStepProvider = StateProvider<int>((ref) => 0);

/// Auto-start gate. Resolves to `true` only when:
///   * the persisted `arl_tour_seen_v2` flag is unset / "false"
///   * the tour is not already active
///
/// Implemented as a FutureProvider that reads secure storage directly
/// — the previous Provider<bool> watched [tourSeenProvider]'s
/// synchronous `false` default and fired auto-start *before* the
/// async storage read updated the in-memory flag. That race made the
/// tour reopen on every cold launch.
///
/// Consumers MUST gate on `.when(data: ..., loading: ..., error: ...)`
/// so the auto-start callback only fires after we've confirmed the
/// persisted state. See `MainScaffold` for the canonical pattern.
final tourShouldAutoStartProvider = FutureProvider<bool>((ref) async {
  final active = ref.watch(tourActiveProvider);
  bool seen = false;
  try {
    final raw = await _storage.read(key: _kTourSeenKey);
    seen = raw == 'true';
    // Keep the in-memory mirror in sync so any other consumer reading
    // [tourSeenProvider] sees the persisted value.
    if (seen && !ref.read(tourSeenProvider)) {
      ref.read(tourSeenProvider.notifier).state = true;
    }
  } catch (_) {
    // Secure storage unavailable (unit tests, denied keychain access).
    // Treat as unseen — replay flow can still toggle the tour, and
    // we'd rather show it once than never.
    seen = false;
  }
  return !seen && !active;
});

/// Start the tour. Resets to step 0 and flips active on.
void startTour(WidgetRef ref, {bool isAutoStart = false}) {
  if (isAutoStart && kDebugMode) {
    // Explicit signal so QA can verify the auto-start gate fires only
    // on a true first launch (seen flag absent / "false"). If this log
    // appears on a subsequent launch, the persistence write didn't
    // land — check secure storage and [dismissTour]'s await.
    debugPrint('[tour] auto-start fired (seen = false)');
  }
  ref.read(tourStepProvider.notifier).state = 0;
  ref.read(tourActiveProvider.notifier).state = true;
}

/// Advance one step. If we're past the end, dismiss + mark seen.
Future<void> nextTourStep(WidgetRef ref) async {
  final current = ref.read(tourStepProvider);
  final steps = tourSteps();
  if (current + 1 >= steps.length) {
    await dismissTour(ref);
  } else {
    ref.read(tourStepProvider.notifier).state = current + 1;
  }
}

/// Step back. No-op at index 0 (so the back affordance is just inert
/// rather than missing — saves a conditional in the UI).
void previousTourStep(WidgetRef ref) {
  final current = ref.read(tourStepProvider);
  if (current > 0) {
    ref.read(tourStepProvider.notifier).state = current - 1;
  }
}

/// Dismiss + persist. Used by both "Skip" and the final "Done" CTA.
Future<void> dismissTour(WidgetRef ref) async {
  ref.read(tourActiveProvider.notifier).state = false;
  ref.read(tourStepProvider.notifier).state = 0;
  ref.read(tourSeenProvider.notifier).state = true;
  try {
    await _storage.write(key: _kTourSeenKey, value: 'true');
  } catch (_) {
    // Persistence is best-effort — the session flag covers this run.
  }
}

/// Replay — wired to Profile → "Replay Tour". Clears the seen flag for
/// this session (we don't clear secure storage because the spec says
/// "show once, replayable" — the seen flag is just a hint) and flips
/// the tour on.
Future<void> replayTour(WidgetRef ref) async {
  ref.read(tourStepProvider.notifier).state = 0;
  ref.read(tourActiveProvider.notifier).state = true;
}

