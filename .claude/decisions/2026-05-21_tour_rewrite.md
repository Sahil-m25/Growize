# 2026-05-21 — Tour rewrite: target-keyed arrow overlay

## Status

Locked. Replaces the legacy `TutorialOverlay` 14-step carousel.

## Decision

Discard the full-screen "carousel-with-sample-data" overlay and replace
it with a target-keyed arrow tour. Each step points an animated arrow at
a real widget in the app, with a brand-styled bubble describing what the
target does. The tour walks through every primary screen by self-
navigating via GoRouter.

## Why

The old overlay had two structural problems:

1. **Generic copy + sample numbers.** Every step showed mock values
   ("Rs.1.20 Cr", "Month 9 of 60") next to a generic icon. Once an
   investor had real allocations, the sample numbers contradicted the
   live screen behind the scrim — so we gated the auto-show to empty
   portfolios only, which meant the tour never showed for the people
   who would benefit most.
2. **Nothing actually pointed at the UI.** The overlay covered the
   whole screen, so a step describing "the bell icon top-right" forced
   the user to dismiss the overlay before they could see what the bell
   looked like.

The new tour points at the literal pixel the user needs to find. No
mock data, no abstract icons — the bubble describes whatever real
widget the arrow is touching.

## Architecture

Three new files in `lib/features/onboarding/`:

- **`tour_keys.dart`** — a registry of `GlobalKey` instances, one per
  tour target. Screens attach the matching key to the widget being
  highlighted (`key: TourKeys.notificationBell`) and nothing else
  changes about the screen's layout.
- **`tour_controller.dart`** — `TourStep` model + the ordered step
  list + Riverpod providers (`tourSeenProvider`, `tourActiveProvider`,
  `tourStepProvider`, `tourShouldAutoStartProvider`) + the action
  helpers `startTour`, `nextTourStep`, `previousTourStep`,
  `dismissTour`, `replayTour`. Persistence uses
  `flutter_secure_storage` under the key `arl_tour_seen_v2`.
- **`tour_arrow_overlay.dart`** — the painter widget. Reads the
  current step, navigates via GoRouter to the step's route, awaits a
  frame so the target widget mounts, looks up its `RenderBox` via
  `GlobalKey.currentContext`, computes the global rect, then paints
  the scrim with a rounded-rect cutout, draws a curved gold arrow
  from a brand-styled bubble to the cutout edge.

The overlay sits at the top of the `MainScaffold` Stack, so it covers
every shell route (home / projects / financials / explore / profile /
documents / activity / support). Step content includes a `pushRoute`
flag so detail-style routes (profile, support, documents) are pushed
onto the stack instead of replacing the active tab.

## Step list (21 beats)

| #  | Route        | Target key            | Title                         |
|----|--------------|-----------------------|-------------------------------|
|  1 | /            | — (centered)          | Welcome to Growize            |
|  2 | /            | — (centered)          | Two ways around               |
|  3 | /            | notificationBell      | Notifications                 |
|  4 | /            | profileAvatar         | Your profile                  |
|  5 | /            | portfolioCard         | Portfolio at a glance         |
|  6 | /            | projectProgressCard   | Contract progress             |
|  7 | /            | quickStatsRow         | Active units & next payout    |
|  8 | /            | bottomNavProjects     | Projects tab                  |
|  9 | /projects    | projectsHeader        | Your portfolio                |
| 10 | /projects    | projectsGrid          | Project tiles                 |
| 11 | /projects    | bottomNavFinancials   | Financials tab                |
| 12 | /financials  | financialsTabs        | Payouts & Financials          |
| 13 | /financials  | bottomNavExplore      | Explore tab                   |
| 14 | /explore     | exploreFilters        | Filter & browse               |
| 15 | /explore     | — (centered)          | Open in Maps & Share          |
| 16 | /profile     | profileSecurityTile   | Security                      |
| 17 | /profile     | profileReplayTour     | Replay this tour              |
| 18 | /support     | supportWhatsappTech   | WhatsApp Tech & RM            |
| 19 | /documents   | — (centered)          | Documents vault               |
| 20 | /activity    | — (centered)          | Activity timeline             |
| 21 | /            | — (centered)          | You're set                    |

Copy follows the brand voice — short, friendly, useful. No "click here"
filler. Example: _"Your bell glows gold when there's something new — a
payout, a phase update, a fresh document."_

## Visual style

- **Scrim** — charcoal 80% (`#0F1A15CC`) with a rounded-rect cutout
  (radius 14) around the inflated target rect (default 8px padding,
  configurable per step).
- **Cutout ring** — 2px gold (`#D4AF37` alpha=0.85) so the target
  stands out without flashing.
- **Arrow** — quadratic Bezier in gold (2.5px stroke), small filled
  triangle head; control point perpendicular to the line so the arc
  reads as a "playful nudge" rather than a stiff line. Suppressed on
  centered steps.
- **Bubble** — cream background, 1.5px primary border, 16-radius,
  charcoal text. Inside: a 4x16 gold accent bar + `STEP N OF 21`
  eyebrow, title (16/700), body (12.5/1.45), Back (ghost) + Next/Done
  (primary). Slides in 220ms with a 0.05y offset on every step
  transition via `AnimatedSwitcher`.
- **Skip link** — bottom-right pill, charcoal 35% chip + white text,
  always visible.

## Persistence + replay

- First successful pass through the tour writes `arl_tour_seen_v2 =
  true` to `flutter_secure_storage`. Auto-start guards on this flag.
- **Replay** — wired to the existing "Replay Tour" tile on
  ProfileScreen, which now calls the new `replayTour(ref)` (and
  `context.go('/')` first, so the welcome lands against live home
  widgets).
- **Skip / Done** — both dismiss the tour and flip the seen flag.
- **Storage failure** — silently falls back to "unseen" so unit tests
  and dev rebuilds can still exercise the tour.

## Files touched

New:
- `lib/features/onboarding/tour_keys.dart`
- `lib/features/onboarding/tour_controller.dart`
- `lib/features/onboarding/tour_arrow_overlay.dart`

Modified (GlobalKey attachments, no layout restructure):
- `lib/core/widgets/arl_app_bar.dart` — logo, bell, avatar
- `lib/core/widgets/main_scaffold.dart` — bottom-nav items;
  TutorialOverlay swapped for TourArrowOverlay; auto-start trigger
- `lib/features/home/home_screen.dart` — portfolio, progress, stats
- `lib/features/projects/projects_list_screen.dart` — header + grid
- `lib/features/financials/financials_screen.dart` — header + tabs
- `lib/features/explore/explore_screen.dart` — filters + grid
- `lib/features/profile/profile_screen.dart` — security + replay
  tiles; replay action retargeted to `replayTour`
- `lib/features/support/support_screen.dart` — WhatsApp Tech CTA

Stubbed (orphaned by the rewrite — file deletion blocked by Cowork
sandbox, contents replaced with a deprecation pointer):
- `lib/features/onboarding/tutorial_overlay.dart`
- `lib/features/onboarding/tutorial_provider.dart`

## Verification

Manual review of the new files passed. `dart analyze lib` must be run
on the Windows host (`& C:\flutter\bin\dart.bat analyze lib`) because
the agent sandbox does not have Flutter installed. The expected
outcome is zero errors; any warnings should appear in unrelated files.

## Open follow-ups

- If Cowork allows file deletion in a future session, drop the two
  legacy stub files (`tutorial_overlay.dart`, `tutorial_provider.dart`).
- Project-detail screen (`/projects/<id>`) is not currently in the
  tour because the route requires a real project id and the tour
  has to work for empty-portfolio investors. Add an "ifProjectExists"
  pre-action when allocations land for everyone — point at the hero
  banner, the 10-stage timeline, and the action tiles.
- Web layout sanity: the overlay reads `MediaQuery.of(context).size`
  for screen extent. On extremely wide desktop browsers the bubble's
  max-width (320 / 360px) keeps things sane, but a future polish pass
  could centre the bubble nearer the target on landscape tablets.
