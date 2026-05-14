# 2026-05-14 — Consolidated stats card on Project Detail

## Problem
UAT:
1. "Invested ₹1.00L" appeared twice — once in the 3-column row, once in the "Invested ₹X · Per-unit ₹Y" subtext beneath.
2. Stats were split: Units / Month / Invested as one row, Per-unit cost as separate subtext line. User wanted a single card with all four data points.

## Fix
- Removed the duplicate `Invested · Per-unit` subtext block.
- Replaced the three `_StatTile` row + subtext with a new `_InvestorStatsCard` that holds all four stats in a 2x2 grid inside one white card. Visual style matches `lib/features/home/widgets/quick_stats_row.dart`: white bg, sand border, soft shadow, per-row icon + small muted label + bold value.
- Tenure now reads as "Month X of Y" (was "X/Y" in a stat tile).
- Per-unit reads "—" when allocation is missing or unitPrice ≤ 0 (matches old behaviour where the subtext was hidden).
- Dropped the now-unused `_StatTile` widget.

## Files changed
- `lib/features/projects/project_detail_screen.dart`

## Verification
`dart analyze lib` clean.
