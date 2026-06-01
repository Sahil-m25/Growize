# 2026-05-21 — Risk vs Return chart: explicit numbers + legend table

Status: **locked**

## Problem

User feedback on the Financials tab Risk vs Return card:

> for risk versus return metrics, I want you to have numbers also. So
> because there are no numbers, it does not understand what is the risk
> versus return that we are getting. Please fix that. Add numbers to it.

Prior state: six labelled dots floated in a 4-tinted-quadrant Stack
with no axes, no gridlines, and no numeric annotations. Each dot had a
two-line label (e.g. "Fixed\nDeposit") in 7 pt grey — readable in
isolation but useless for "what return are we actually getting vs the
benchmark." Growize EKA sat in the top-left quadrant with no number to
back the claim.

## File

`lib/features/financials/financials_screen.dart` — replaced
`_riskReturnCard(BuildContext context)` end-to-end. Added private
classes `_AssetPoint` (data model) and `_AssetLegendRow`
(StatelessWidget) at file bottom, after the existing
`_FinancialsScreenState` class.

## Data model

Six asset classes, each carrying explicit numerics so chart, dot tag,
and legend row all read from the same source of truth:

| Asset          | Return | Risk (1-5) | Label |
|----------------|--------|------------|-------|
| Fixed Deposit  | 7%     | 1.0        | Low   |
| Govt Bonds     | 8%     | 2.0        | Low   |
| Gold           | 8%     | 3.0        | Med   |
| REITs          | 11%    | 3.0        | Med   |
| Direct Equity  | 14%    | 4.0        | High  |
| Growize EKA    | 18%    | 2.5        | Med   |

Sources cited in footer: AMFI · SEBI Guidelines · RBI bond yields
(matches the HTML mockup attribution at lines 904–905 of
`Growize App Design.html`). Numbers align with the HNI-context defaults
in the user brief.

## Chart layout

- Y-axis (left, 26 px column): five tick labels — 20%, 15%, 10%, 5%,
  0% — top-to-bottom, 9 pt primary-green bold, distributed with
  spaceBetween so they sit exactly at the gridline rows.
- X-axis (bottom, 14 px row): six tick labels — 0, 1, 2, 3, 4, 5 —
  spaceBetween across the plot width, padded by 26 px on the left
  to match the Y-label column. Caption "Risk Score (1 = lowest, 5 =
  highest)" beneath.
- Gridlines: 0.5 px sand lines at 25/50/75% of plot height (=
  15%/10%/5% return) and at risk = 1, 2, 3, 4.
- Quadrant tints preserved but desaturated to alpha 0.04–0.07 so the
  numeric tags dominate. Corner labels simplified from four two-line
  tags (LOW RISK / HIGH RETURN etc.) to two single-word markers
  ("IDEAL ZONE" top-left, "AVOID" bottom-right) at alpha 0.55.
- Dot positioning is now computed directly from data:
  x = (risk / 5) * w, y = (1 - return / 20) * h. Previously the
  rx, ry constants were hand-tuned 0..1 coordinates with no
  relationship to actual numbers.
- Dot tag sits to the right of each dot in a tiny pill (white bg,
  0.5 px sand border, 8.5 pt charcoal, 9.5 pt for the star).
  Format: "7% · R1" for benchmark assets, "Growize EKA 18% · R2.5"
  for the star. Tag width is capped at 140 px via a ConstrainedBox.

## Legend table (new)

A 6-row table below the chart, inside the same card, with a 9 pt
all-caps header (ASSET / RETURN / RISK):

1. Growize EKA — 18% — Med · R2.5 ← gold-tinted row, primary-green
   text, white-on-primary "YOU" pill next to the name
2. Direct Equity — 14% — High · R4
3. REITs — 11% — Med · R3
4. Govt Bonds — 8% — Low · R2
5. Gold — 8% — Med · R3
6. Fixed Deposit — 7% — Low · R1

Sorted descending by return so the best yield is the first thing the
eye lands on. Each row has the same colored dot as the chart so the
visual mapping is immediate.

## What changed visually

- Before: chart 220 px tall, 6 colored dots with two-line labels,
  no axes, four quadrant tints, no numeric annotation anywhere,
  "Source: AMFI · SEBI Guidelines" footer.
- After: chart 210 px + 14 px X-axis row + ~12 px caption + ~140 px
  legend table. Six dots in data-driven positions, each carrying a
  "N% · RN" tag. Y-axis ticks on the left (20% / 15% / 10% / 5% /
  0%), X-axis ticks on the bottom (0 / 1 / 2 / 3 / 4 / 5),
  gridlines at every tick. Sorted legend table beneath the chart
  with Growize highlighted.

## Decisions / trade-offs

- Inline closures vs. private methods. dotWithLabel, axisLabel, and
  riskStr are inline closures in _riskReturnCard because they
  capture xMax/yMax/assets and aren't used elsewhere. Legend row
  got a real class because it has structural depth and benefits
  from const construction.
- Risk scale 1-5 instead of Low/Med/High alone. The existing chart
  already implied a continuous X axis. Growize at 2.5 communicates
  more than the categorical bucket alone. The riskLabel string is
  shown alongside the number ("Med · R2.5") so users get both.
- Number formatting. Return shown as integer % (18%) — the
  granularity is "what should investors expect this year." Risk
  shown as integer when whole (R1, R4) and one decimal when half
  (R2.5) via a small riskStr() helper.
- Growize at risk 2.5, not 3. The brief listed Growize at Medium /
  3; the HTML mockup placed it at Risk 1.5. Compromise: 2.5 — left
  edge of the Medium bucket, preserves the "low-to-moderate risk,
  high return" story.
- No new packages. The chart is still hand-positioned widgets inside
  a LayoutBuilder + Stack — no fl_chart added.
- Star asset tag carries the name so users can locate Growize on
  the chart; benchmark tags show numbers only.

## Removed

- RotatedBox vertical "Return →" label — replaced by tick numbers.
- The "Risk →" centered footer label — replaced by numeric X ticks
  plus a "Risk Score (1 = lowest, 5 = highest)" caption.
- Four corner quadrant two-line labels — reduced to two minimal
  hints (IDEAL ZONE / AVOID).
- Two-line dot labels ('Fixed\nDeposit', etc.) — names live in the
  legend table now; the chart shows numbers only.

## Verify

`& C:\flutter\bin\dart.bat analyze lib` — must be run on the user's
Windows machine; the agent sandbox does not have a Flutter toolchain.
The changes are self-contained inside financials_screen.dart: no new
imports, no public API change, no provider rewiring. The existing
"// ignore: unused_element" comment on _capitalRow is preserved.

## Files touched

- lib/features/financials/financials_screen.dart — replaced
  _riskReturnCard, added _AssetPoint and _AssetLegendRow classes at
  end of file.
- .claude/decisions/2026-05-21_risk_return_numbers.md (this file).
- .claude/INDEX.md — added index row.
