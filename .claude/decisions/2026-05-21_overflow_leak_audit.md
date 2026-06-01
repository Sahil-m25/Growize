# Audit: decorative-element visual leaks across lib/

**Date:** 2026-05-21
**Status:** locked
**Phase:** Verify

## Context
Earlier today we fixed a visible leak in
`lib/features/home/widgets/portfolio_card.dart`: the gradient hero card
in a `Stack` contained a `Positioned(top: -30, right: -30,
child: Container(circle, gold))` decoration intended to peek out of the
rounded-15 card corner. The Stack wasn't wrapped in a `ClipRRect`, so
the gold circle bled visibly into the page background.

Fix that landed:
`Padding(EdgeInsets.all(16)) > ClipRRect(BorderRadius.circular(15))
> Stack > [card Container, Positioned decoration]`.

This audit sweeps `lib/` for any other instance of the same pattern —
decorative content positioned at negative offsets relative to a
rounded-rect parent — and classifies each as Leaking / Intentional /
Safe.

## Search signals used
- `top: -`, `bottom: -`, `left: -`, `right: -` — negative Positioned offsets
- `Transform.translate` — translated content that could overflow
- `Positioned\(` — every Stack child placement (14 files matched)
- `OverflowBox` / `SizedOverflowBox` — explicit overflow widgets
- `IntrinsicHeight` / `IntrinsicWidth` — height/width box that can interact badly with infinite extents
- `shape: BoxShape.circle` — circular decorations that could overflow
- `clipBehavior` — existing clip handling on Stacks/Containers

## Findings

### Negative-offset Positioned children
Only two sites in `lib/` use negative Positioned offsets:

**1. `lib/features/home/widgets/portfolio_card.dart` — Fixed (reference)**
   - Gold decorative circle at `top: -30, right: -30` inside a Stack
     whose first child is the gradient card with `BorderRadius.circular(15)`.
   - Already wrapped in `Padding > ClipRRect(15) > Stack` per the
     reference fix earlier today. No change needed in this audit.

**2. `lib/core/widgets/arl_app_bar.dart` — Intentional, left alone**
   - Notification badge at `Positioned(top: -2, right: -2, ...)` inside
     `Stack(clipBehavior: Clip.none, ...)` containing the bell icon.
   - The Stack lives inside `Padding(EdgeInsets.all(8))` inside an
     `InkWell` with `borderRadius: BorderRadius.circular(20)`.
   - InkWell's borderRadius only clips the splash/highlight — not the
     children — so the badge does not collide with a rounded edge.
   - The badge has a 2px cream border (`ArlColors.cream`, matching the
     AppBar background), so it visually separates from the icon
     cleanly against the cream surface.
   - This is the standard Material notification badge pattern. The
     explicit `Clip.none` is intentional. Wrapping in a `ClipRRect`
     would clip the badge into the bell icon's bounding box and
     defeat the purpose. No fix.

### Positive-offset Positioned children inside rounded parents
All other `Positioned(...)` sites use positive offsets and already sit
inside parents that clip them appropriately. Confirmed safe:

- `lib/features/explore/explore_detail_screen.dart` hero banner —
  already wrapped in `ClipRRect(BorderRadius.circular(16))`.
- `lib/features/explore/widgets/project_tile.dart` — outer Container
  has `clipBehavior: Clip.antiAlias` on a rounded-16 card.
- `lib/features/explore/widgets/share_project_modal.dart` preview card
  — outer Container has `clipBehavior: Clip.antiAlias` on rounded-16.
- `lib/features/projects/projects_list_screen.dart` card — outer
  Container has `clipBehavior: Clip.antiAlias` on rounded-16.
- `lib/features/projects/project_view_area_screen.dart` map preview —
  `ClipRRect(BorderRadius.vertical(top: Radius.circular(15)))`
  already wraps the Stack.
- `lib/features/projects/widgets/project_hero_banner.dart` — full-bleed
  banner with no border radius; nothing to leak against.
- `lib/features/gallery/gallery_screen.dart` photo tile — already
  wrapped in `ClipRRect(BorderRadius.circular(8))`.
- `lib/features/financials/financials_screen.dart` risk/return chart —
  `Stack(clipBehavior: Clip.hardEdge)` on the quadrant grid; the
  per-dot helper's `left: x - size/2` can dip just below 0 when a dot
  sits on the axis, but the hardEdge clip catches it.
- `lib/features/projects/project_photos_screen.dart` — full-screen
  lightbox, no rounded edge.
- `lib/features/celebration/celebration_screen.dart` confetti header
  — full-bleed `SizedBox(height: 280)`, sparkle icons at safe
  positive offsets, no rounded edge to leak against.
- `lib/features/onboarding/tour_arrow_overlay.dart` — overlay drawn
  at the screen root; no rounded parent.

### Transform.translate
No matches in `lib/`.

### OverflowBox / SizedOverflowBox
No matches in `lib/`. No unclipped overflow boxes exist.

### IntrinsicHeight uses
Four sites, all wrapping bounded-width Rows so
`CrossAxisAlignment.stretch` gets a finite vertical extent. None wrap
infinite-height content. Confirmed safe:

- `lib/features/home/widgets/quick_stats_row.dart`
- `lib/features/projects/widgets/project_action_tiles.dart`
- `lib/features/projects/widgets/phases_timeline.dart`
- `lib/features/explore/explore_detail_screen.dart`

### TODO / overflow comments
No `TODO overflow`, `TODO width`, or similar markers found in `lib/`.

## Outcome

| Bucket                 | Count | Files |
|------------------------|-------|-------|
| Fixed (reference)      | 1     | `lib/features/home/widgets/portfolio_card.dart` (fix landed pre-audit) |
| Intentional, left alone| 1     | `lib/core/widgets/arl_app_bar.dart` |
| Ambiguous, flagged     | 0     | — |

No new code changes were made by this audit. The portfolio card fix
was the only true leak in the codebase. The AppBar notification badge
looks superficially similar but does not leak against any rounded
surface and is the standard pattern.

## Verification
- No file edits were applied during this audit, so `dart analyze`
  state is unchanged from the post-portfolio-card-fix baseline.
- Re-run with: `& C:\flutter\bin\dart.bat analyze lib`.
