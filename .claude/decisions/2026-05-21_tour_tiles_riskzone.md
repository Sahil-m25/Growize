# Tour auto-skip + project tile aspect + Risk vs Return ideal zone

Date: 2026-05-21
Status: locked
Scope: three small UX fixes bundled under one decision since they
touched separate features and don't share machinery.

## 1. Tour gracefully handles missing targets

### Problem

The tour was authored against a "happy path" investor — one with at
least one project, a loaded portfolio cluster, and every screen widget
mounted. Two of the 21 steps point at conditionally rendered targets:

- Step 10 (`projectsGrid`) — only rendered when `projects.isNotEmpty`.
  A brand-new investor with zero allocations would see the empty-state
  text and the tour would freeze on that step with the cutout pointed
  at empty space.
- Steps 5-7 (`portfolioCard`, `projectProgressCard`, `quickStatsRow`)
  — only rendered after the first portfolio fetch lands. On cold
  start with a slow network the tour could land on these before the
  data arrives.

The previous overlay scheduled one post-frame retry when a target was
missing but didn't bound the wait, so the tour just sat there.

### Decision

Auto-skip steps whose target doesn't mount within
`_maxRetriesPerStep` settle passes (2 frames). If
`_consecutiveSkippedSteps` exceeds `_maxConsecutiveSkips` (3) we jump
to the closer step so the tour ends on a "you're set" card instead of
walking the user past empty cutouts.

Logged via `debugPrint` so the skip path is visible in
`flutter logs`: `[tour] skipped step N (Title) — target [GlobalKey...]
not in tree`.

### 21-step inventory

| # | Title | Target | Classification |
|---|---|---|---|
| 1 | Welcome to Growize | — (center) | always |
| 2 | Two ways around | — (center, intro) | always |
| 3 | Notifications | `notificationBell` | always (app bar on every shell route) |
| 4 | Your profile | `profileAvatar` | always (app bar) |
| 5 | Portfolio at a glance | `portfolioCard` | conditional (first portfolio fetch must land) |
| 6 | Contract progress | `projectProgressCard` | conditional (cached portfolio required) |
| 7 | Active units & next payout | `quickStatsRow` | conditional (cached portfolio required) |
| 8 | Projects tab | `bottomNavProjects` | always (main scaffold) |
| 9 | Your portfolio | `projectsHeader` | always (header column renders even with zero projects) |
| 10 | Project tiles | `projectsGrid` | **conditional** (omitted when `projects.isEmpty`) |
| 11 | Financials tab | `bottomNavFinancials` | always |
| 12 | Payouts & Financials | `financialsTabs` | always |
| 13 | Explore tab | `bottomNavExplore` | always |
| 14 | Filter & browse | `exploreFilters` | always |
| 15 | Open in Maps & Share | — (center) | always |
| 16 | Security | `profileSecurityTile` | always |
| 17 | Replay this tour | `profileReplayTour` | always |
| 18 | WhatsApp Tech & RM | `supportWhatsappTech` | always |
| 19 | Documents vault | — (center) | always |
| 20 | Activity timeline | — (center) | always |
| 21 | You're set | — (center) | always |

Worst case brand-new-investor walkthrough: steps 1-4 render → 5-7 may
skip while portfolio fetch is in flight → 8-9 render → step 10 skips
(no grid) → 11+ render. The closer-jump only triggers if four
contiguous steps skip, which would require both the portfolio cluster
AND the projects grid to be missing — at which point ending the tour
on the "you're set" card is the right call.

### Files

- `lib/features/onboarding/tour_arrow_overlay.dart` — added retry
  counters and skip logic to `_settle()`. No change to the public
  surface.

### Not done

The `cutoutPadding` and `arrowSide` per step weren't changed; they
match the rect-relative geometry which the auto-skip path never reaches.

---

## 2. Project tiles slightly elongated

### Problem

User feedback: tiles looked cramped under the 16:10 hero — the four
body rows (crop chip, units, progress bar, payout footer) sat tight
against the bottom edge.

### Decision

`childAspectRatio` 0.95 -> 0.87 (about 8.5% taller). Tile width stays
fixed by `maxCrossAxisExtent: 220`; only the vertical dimension grows.

### Files

- `lib/features/projects/projects_list_screen.dart` — one-line change
  inside `SliverGridDelegateWithMaxCrossAxisExtent`.

---

## 3. Risk vs Return — Growize position + explicit Ideal Zone

### Problem

Growize EKA was plotted at risk 2.5, return 18% — in the top half of
the chart but in the middle horizontally. The user wanted it left of
center to read as "low-risk, high-return" and asked for a clearer
"ideal zone" overlay.

### Decision

1. Move Growize EKA from `risk = 2.5` to `risk = 1.8`. Return stays
   at 18% — that's the headline number.
2. Add an explicit Ideal Zone overlay: translucent green
   (`ArlColors.accent` alpha 0.10) rounded rectangle with a soft 1px
   border (alpha 0.35), spanning risk 0-2.5 and return 12-20%.
3. Reposition the "IDEAL ZONE" corner narrative into the rectangle
   itself, restyled as muted italic ("Ideal Zone") so it reads as a
   label on the overlay rather than a corner watermark.

Growize EKA at (1.8, 18) renders inside the rectangle (zone center is
risk 1.25, return 16%; Growize sits slightly above center, comfortably
left of the right edge at risk 2.5). The legend table auto-updates to
show `R1.8` because `riskStr()` already formats half-step risks.

### Files

- `lib/features/financials/financials_screen.dart` — updated the
  `_AssetPoint('Growize EKA', ...)` row, added `idealRiskMax` /
  `idealReturnMin` constants, layered a labeled rounded-rect overlay
  over the existing quadrant tints.

### Not done

- The four-quadrant background tint is kept (top-left tint is slightly
  lighter to let the explicit overlay breathe).
- The legend table layout is unchanged; only the printed risk value
  shifts because it reads from the asset's `risk` field.

---

## Verification

`& C:\flutter\bin\dart.bat analyze lib` — Flutter is not installed in
the agent sandbox so the analyzer was not executed here. Run on the
dev machine before shipping.

No new packages added.
