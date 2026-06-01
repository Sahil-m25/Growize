# Tour overlay — dynamic geometry (resize / scroll / rotate)

**Date:** 2026-05-21
**Status:** locked
**Files touched:**
- `lib/features/onboarding/tour_arrow_overlay.dart` (rewritten)
- `.claude/decisions/2026-05-21_tour_dynamic_geometry.md` (this file)
- `.claude/INDEX.md` (row added)

## Problem

The new tour overlay (introduced in `2026-05-21_tour_rewrite.md`) painted
the cutout, arrow, and bubble using geometry computed **once** per step.
That meant:

- Resizing the Chrome window during a step left the cutout at the old
  rect — the gold ring and arrow no longer pointed at anything.
- Targets below the fold (`bottomNavProjects` when a tall header pushed
  it out of view) never got pulled into view, so the cutout drew at
  the old coords or off-screen.
- The bubble was sized against a hard-coded `bubbleH = 170` estimate;
  taller body copy bled past the bottom and got clipped by the Skip
  pill, while shorter copy left an awkward gap before the arrow body.
- Only `above`/`below` auto-flipped — preferred `left`/`right` could
  push the bubble off-screen when the target was near the viewport
  edge.
- The arrow's control-point sign was hard-coded per-axis, so on
  cramped layouts the curve bowed *away* from the target instead of
  wrapping around it.

## Root cause

Three independent layers of staleness:

1. **No metric listener.** No `WidgetsBindingObserver.didChangeMetrics`
   on the overlay state, so device rotate / window resize never
   triggered a rebuild. `MediaQuery` did rebuild eventually but the
   cached `_rectTick` wasn't bumped.
2. **One-shot rect read.** `_targetRect()` was called inside `build`
   only when `_rectTick` bumped (init, step change, or a single
   post-frame retry). Layout reflows *after* the step settled — scroll,
   header collapse, AnimatedSwitcher resize — never re-ran the lookup.
3. **Estimated bubble size.** Positioning used a constant `bubbleH`.
   Real bubble height could be ±40px off, which threw the arrow origin
   and the side auto-flip's headroom check off too.

## Fix

`TourArrowOverlay` state now:

- Adds `WidgetsBindingObserver`; `didChangeMetrics` -> `setState`.
- Owns a `Ticker` (via `SingleTickerProviderStateMixin`) that re-reads
  the target's `RenderBox.localToGlobal(Offset.zero) & renderObject.size`
  every frame, plus the bubble's measured size via a `GlobalKey`.
  `setState` only fires when one of them moves by more than 0.5 px,
  so the rebuild cost is paid only when geometry actually changed.
- Wraps the painter in a `LayoutBuilder`, so paint-box constraints are
  the live ones for that frame.
- After step change / route nav: calls `Scrollable.ensureVisible` on
  the target's context (wrapped in `try/catch` for targets that aren't
  inside a scrollable). The target slides into the viewport with a
  240ms ease, then the per-frame ticker re-points the cutout.
- Measures the bubble via a `GlobalKey` attached outside
  `AnimatedSwitcher` (using `KeyedSubtree`), so the key never collides
  with the switcher's child-keying. First frame uses an estimate, the
  next frame uses the real size.
- `_resolveSide` now checks clearance on **all four sides** plus the
  safe-area inset, picks the preferred side if it fits, otherwise the
  side with the most clearance that fits, otherwise the raw-largest
  side as a last resort.
- `_positionBubble` clamps both axes into the safe area and reserves
  68px at the bottom for the Skip pill — bubble and Skip can no longer
  collide.
- `_bubbleArrowOrigin` slides along the bubble edge toward the anchor
  when the safe-area clamp has shifted the bubble off-centre relative
  to the target, so the arrow still reads as "from bubble to target".
- `_ArrowPainter` now computes its control-point as a unit perpendicular
  to the (from -> to) line, with sign chosen by the dot product against
  (target.center - midpoint). Magnitude is `0.30 * line_length`, so the
  curve scales with arrow length and always bows *toward* the target.
- Arrowhead remains a filled triangle along the tangent at t=1; gold
  `#D4AF37`, 11px tip, 2.5px stroke. Cutout radius stays 14, padding 8
  (4 for cards).

The 21-step `TourStep` list and the `TourKeys` registry are unchanged.
Only the painter / positioner / state-driver was touched.

## How to test (smoke)

1. **Resize Chrome.** Run on web, start the tour from Profile -> Replay,
   advance to step 3 (notification bell). Drag the Chrome window from
   1280px wide down to 360px. The cutout and arrow should track the
   bell live; the bubble flips above/below as available space changes.
2. **Below the fold.** Advance to step 7 (`bottomNavProjects`). On a
   short window, the bottom nav should slide into view automatically
   thanks to `Scrollable.ensureVisible`, and the arrow lands on the
   Projects tab.
3. **Long header.** Sign in with a long display name that pushes the
   header content. Step 4 (`profileAvatar`) — the cutout should still
   align with the avatar's current screen position, not its position
   at first paint.
4. **Mobile rotate.** Build to Android, start tour, rotate the device
   landscape <-> portrait while a step is showing. `didChangeMetrics`
   forces a rebuild; ticker re-measures; cutout settles cleanly.
5. **Safe-area edge cases.** On iPhone with notch, confirm bubble
   never bleeds under the notch (top safe-area pad) or the home bar
   (bottom safe-area pad).
6. **Side auto-flip.** Mock a target whose preferred side is `right`
   but which is hard against the right edge — bubble should flip to
   `left` automatically.

## Rejected alternatives

- *Use `OverlayPortal` + `CompositedTransformFollower`.* Cleaner long
  term, but requires attaching a `LayerLink` per target — that's a
  bigger surgery than the brief allowed and would touch every screen
  that registers a `TourKeys.*`.
- *`MediaQueryData` listener via `InheritedWidget`.* Already does this
  implicitly through `MediaQuery.of(context)`, but doesn't fire on
  scroll / header collapse. The ticker covers both cases for free.
- *Drop `Scrollable.ensureVisible`.* Cheaper, but the brief
  specifically calls for auto-scrolling off-screen targets into view.
  Wrapped in `try/catch` so non-scrollable targets are a no-op.

## Verify

Run from PowerShell on Windows:

```
& C:\flutter\bin\dart.bat analyze lib
& C:\flutter\bin\flutter.bat run -d chrome
```

Then resize the Chrome window while the tour is open — cutout, arrow,
and bubble should follow the target widget in real time.
