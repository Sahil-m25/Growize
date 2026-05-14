# 2026-05-14 — Wire "View Area" button on Project Detail

## Problem
UAT: tapping "View Area" did nothing — `onPressed: () {}`.

## Fix
Added `onViewArea` callback prop on `_Hero`, passed `() => context.push(RouteNames.locationPath(widget.projectId))` from the parent. Route is already registered at `/location/:projectId` rendering `LocationScreen`.

## Files changed
- `lib/features/projects/project_detail_screen.dart`

## Verification
`dart analyze lib` clean.
