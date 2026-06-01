# 2026-05-21 — UI polish round (tiles, phase card, support phones, share preview)

Status: **locked**

A bundle of four discrete UI fixes shipped together so the visual cleanup
lands in one polish pass rather than four scattered patches.

## 1. Projects list tile compaction

**File:** `lib/features/projects/projects_list_screen.dart`

- `SliverGridDelegateWithMaxCrossAxisExtent.childAspectRatio` 0.62 -> 0.95.
  At the previous ratio the tile was ~278 px tall for a 173 px wide cell
  (iPhone 14 width), and the body Column was filling the empty vertical
  space with `mainAxisAlignment: spaceBetween`, producing visible gaps
  between rows.
- Body wrapper changed from `Expanded(child: Padding(... Column(spaceBetween)))`
  to `Padding(... Column(mainAxisSize: MainAxisSize.min))`. The tile now
  sizes its content to itself instead of stretching to fill.
- Internal padding tightened 10 -> 8, inter-row gaps 6 -> 4.
- Net effect: tiles read as compact, slightly-tall squares, no empty
  band under the "Next payout" line.

## 2. Current Phase card compaction

**Files:**
- `lib/features/projects/widgets/phase_timeline_6.dart`
- `lib/features/projects/project_detail_screen.dart` (`_CurrentPhaseCard`)

Timeline node sizing: 36-48 px range -> 28-32 px range. Inner vertical
padding 4 -> 2 px. Label font 9.5 -> 9. Connector between the two snake
rows replaced - the previous vertical 14 px line + 18 px `arrow_drop_down`
chevron (~36 px total) is now a single 14 px `keyboard_arrow_down`
chevron with 2 px breathing room (~18 px total).

Card header condensed:
- Outer padding `EdgeInsets.all(14)` -> `fromLTRB(10, 10, 10, 8)`.
- Icon disc 36 -> 26 px.
- Two-line "CURRENT PHASE / <stage name>" header replaced with a single
  RichText row ("Current Phase  <stage name>") that truncates with
  ellipsis on narrow widths.
- Stage pill text shortened from "Stage N of 10" -> "N/10".
- Spacer between header and timeline 12 -> 6 px.

Estimated card height drop on a 390 px-wide phone: ~340 px -> ~200 px.
Within the requested 180-220 px target.

## 3. Support phone numbers - single source of truth

**Files:**
- `lib/core/constants/support_contacts.dart` (new, 15 LOC)
- `lib/features/support/support_screen.dart`

Both WhatsApp CTAs were pointed at the placeholder `+919999999999`. New
constants module exposes `kRmPhone` (`+917022268125`) and `kTechPhone`
(`+919699928661`). The Support screen imports these and the local
private `_rmPhone` / `_techPhone` consts are removed.

Repo-wide grep confirmed no other `wa.me`, `tel:`, "Talk to RM" or
"Tech support" deep links exist outside `support_screen.dart`, so a
single edit covers every entry point in the current build.

## 4. Share Project preview redesign

**File:** `lib/features/explore/widgets/share_project_modal.dart`

The preview was a busy three-band 1080x1080 mockup - hero, stat-tile
trio with backgrounds + borders, then a brand-coloured RM contact panel
with placeholder name/phone and a tagline strip. Replaced with a
deliberately minimal portrait card:

- Card 280 x 420, radius 16, shadow `Color.fromARGB(40, 0, 0, 0)`,
  blur 20, offset `(0, 8)`.
- Top 5/9: hero image full-bleed, soft black gradient over the lower
  40%, project name (24pt SemiBold cream) + location (12pt 85% cream)
  overlaid bottom-left.
- Bottom 4/9: three minimal stat blocks (Total Units, Area (acres),
  Tier). Labels 10pt muted, values 16pt SemiBold charcoal, no icons,
  no border between stats. The Tier value is the single accent - a
  small gold pill - so the otherwise monochrome bottom half has one
  intentional colour.
- Tiny `growize` wordmark bottom-right (12pt 70% muted).

Removed from the preview: personalisation chip on the hero, "Personalized
for ..." note above the preview, stat tiles' coloured backgrounds and
borders, crop chip, "TALK TO US" RM contact strip (with hard-coded
"Rajesh Kumar / +91 98XXX XXXXX" placeholder data), "growize . by ARL"
double wordmark, and the italic tagline.

Action buttons below the card (WhatsApp + Share Link) and the
caption text field are unchanged. The optional widget parameters
(`growingTech`, `yieldLabel`, `cropLabel`) are retained for API
compatibility with the existing Explore-detail caller - they are no
longer rendered on the simplified preview but stay available for the
v1.1 PNG export pipeline.

## Verification

- `dart analyze lib` not run from the sandbox (no Dart toolchain on the
  shell). Manual code review confirms no obviously-broken references.
  Maintainer should run the analyze command listed in `CLAUDE.md`
  before shipping.
- Line-count deltas:
  - `projects_list_screen.dart` 533 -> 520 (-13)
  - `phase_timeline_6.dart` 463 -> 458 (-5)
  - `project_detail_screen.dart` 921 -> 913 (-8)
  - `support_screen.dart` 498 -> 492 (-6)
  - `share_project_modal.dart` 827 -> 577 (-250)
  - `support_contacts.dart` (new) +15
