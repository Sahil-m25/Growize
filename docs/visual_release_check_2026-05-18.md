# Visual Release Check — 2026-05-18 (run 2026-05-19, re-verified 2026-05-20)

Side-by-side verification of the release-mode Flutter web build against
`Growize App Design v2 (proposed).html` and the user's stated complaints
from the prior round of feedback. Run against `flutter build web --release`
served from `build/web/` on `http://localhost:5000/` via Chrome MCP. All
screenshots captured live from the running app at the mobile viewport
(378×644). No mocked output.

## Environment

| Item              | Value                                                |
|-------------------|------------------------------------------------------|
| Build             | `flutter build web --release`                        |
| Serve             | `python -m http.server 5000` from `build/web/`       |
| URL               | `http://localhost:5000/`                             |
| Viewport          | 378 × 644 (mobile preset)                            |
| Auth              | Logged in via existing session in the MCP tab        |
| Bootstrap         | clean (`flutter_bootstrap.js` 200, no 503s)          |
| CanvasKit         | loaded from gstatic                                  |
| Investor          | sahil Mohite (ARL-002) · 3 projects · ₹3.92 Cr       |

First attempt found the server was running from the project root, which
caused `flutter_bootstrap.js` to 503 because `<base href="/">` makes
Flutter request assets from the server root. After the user restarted
the server inside `build/web/`, the app booted cleanly.

## Priority 1 Screens

### Project Detail — `/projects/<id>` — PASS

Verified on **Pineapple Enterprises**. All four user-stated requirements
present and rendering:

- Hero banner — gradient backdrop, "PE" mark, project name, Premium tier
  badge top-right, back arrow top-left.
- Your Investment 4-tile grid — Units Owned 3 · Total Invested ₹75.00L
  · Expected Return 19% annual · Payouts to Date ₹0 since Apr 2026.
- **Contract Progress bar** — visible, 0%, "Jan 2026 · 4 yrs 8 mos left
  · Jan 2031" — matches v2 spec line `Contract Progress line (slimmer)`.
- Phase timeline — 6-stage (Land · Soil · Greenhouse · Planting ·
  Harvest · Full Ops), Stage 1 of 6 marker on the current phase,
  matches v2 spec `phase-dot done/current` markup.
- Action tiles — **View Area + Photos only**, **NO Documents tile**.
  Matches the v2 `R5: 2 CTA tiles (Documents tile removed)` comment.
- Recent Payouts, Monthly Updates, projection callout, Share Project,
  and Request Exit blocks all present.

### Explore Detail — `/explore` (Alpha Avocado LLP-demo) — PARTIAL

Primary user complaint **resolved**:

- 3 stat tiles only: Units Available 500/500 · Price per Unit ₹0.2 L
  · Expected Return 23% per annum. **No Min Lock-in tile.**
- Hero banner with COMING SOON pill and 1 CR badge.
- Request Consultation + Share Project CTAs at the bottom.
- Aeroponic technique strip with Water saved / Yield / Cycles
  sub-stats (additional content beyond the v2 spec).

Deviations from `page-explore-detail` in v2-proposed (not part of the
user's stated complaints, leaving as-is unless prioritised):

- v2 spec lays out Expected Annual Return as a `col-span-2` full-width
  tile with a `trending-up` icon; Flutter renders it as a smaller
  centred pill between the Units/Price row and the info banner.
- v2 has Crop + Subscription Deadline tiles below the EAR; Flutter
  omits these, substituting the Aeroponic technique strip.
- v2 has View Area + Photos CTA tiles before the bottom CTAs; Flutter
  shows only an "Approximate location" map placeholder.

### Notification Bell — header on every screen — PASS

Code reviewed at `lib/core/widgets/arl_app_bar.dart:22-117`. Behaviour
matches the user's spec exactly:

- 0 unread → `Icons.notifications_outlined`, colour `ArlColors.charcoal`
  (visually verified: outlined dark bell, no badge, on every screen
  walked).
- ≥1 unread → `Icons.notifications_active`, colour `ArlColors.gold`,
  plus a small `ArlColors.earth` rounded badge rendering the count
  (or `9+` if the count exceeds 9), with a 2 px cream border for
  contrast against the cream header. Visual verification of the
  ≥1 state not possible — investor has 0 notifications.

### Support — `/support` — PASS

Reached via Profile → Assistance. Renders exactly per the v2 spec:

- Title "Assistance" with back arrow.
- "GET HELP FAST" subheading.
- Two WhatsApp CTAs at the top, green `#25D366` circles with the
  message-circle icon: "WhatsApp Tech Support — Quick reply for app
  issues" and "WhatsApp Your RM — Account, payouts, investment
  queries".
- "Detailed Request — For less urgent matters · ~24h response" demoted
  below in a sand-tinted card with an "Open form" pill button.
- "My Tickets" header below (empty list in this account).

### Share Project Modal — FAIL → fixed in code → **PASS (re-verified 2026-05-20)**

Tapping Share Project on the Project Detail screen previously produced
the toast `Share modal coming soon — link copied placeholder`. Root
cause: the button at
`lib/features/projects/project_detail_screen.dart:271-280` still
invoked a SnackBar placeholder even though a full `ShareProjectModal`
widget already exists at
`lib/features/explore/widgets/share_project_modal.dart` (used from
Explore Detail).

**Fix applied** (run 2026-05-19):

- Added imports for `ShareProjectModal` and `MarketplaceProject` to
  `project_detail_screen.dart`.
- Added a private `_openShare(Project, InvestorUnit?)` helper that
  bridges the owner-side `Project` into the `MarketplaceProject` shape
  the modal expects — `unitsAvailable` defaults to 0, `pricePerUnit`
  derives from `investedAmount / totalUnits`, `expectedAnnualReturnPct`
  comes from the investor's allocation (fallback 14%).
- Replaced the SnackBar onPressed with `() => _openShare(project,
  allocation)` and passed `ShareMode.owner` so the modal header label
  reads "Share Project" rather than the explorer/celebration variant.

**Re-verification (2026-05-20, after `flutter build web --release`
rebuild and hard reload):**

- Opened Pineapple Enterprises from the Projects tab, scrolled to the
  bottom of the Project Detail screen, tapped **Share Project**.
- A bottom-sheet modal slid up cleanly — no SnackBar, no crash.
- Modal header reads `INVESTOR MODE · Share · Pineapple Enterprises`
  with a close `X` top-right.
- Personalisation note: "Personalized for Sahil Kumar · appears on the
  card and in the caption." with a `1080 × 1080 preview` sublabel.
- Preview card renders: "Shared by Sahil Kumar" badge top-left,
  `PREMIUM` tier badge top-right, hero photo area, project title
  `Pineapple Enterprises`, 3 stat tiles (RETURN 19% · YIELD — · TECH
  Aeroponic), `TALK TO YOUR RELATIONSHIP MANAGER` strip with `RK`
  avatar, `Rajesh Kumar` and phone (masked), `Growize · by ARL` footer
  with tagline.
- Share action row: **Share on WhatsApp** (green primary) ·
  **Email** · **Copy link** — all three CTAs present and tappable.
- Close `X` dismisses the modal and returns to Project Detail
  cleanly.

One minor deviation from the verification spec: there is **no
free-text edit-caption field** in the modal — personalisation is
pre-baked from the investor profile (Sahil Kumar) and applied to both
the card overlay and the share caption. Not blocking; flagging for
product to confirm whether an editable caption is desired.

## Priority 2 Screens

| Screen          | Route                | Status   | Notes                                                                 |
|-----------------|----------------------|----------|-----------------------------------------------------------------------|
| Home dashboard  | `/`                  | PASS     | Total Portfolio Value ₹3.92 Cr, Contract Progress list, Active Units. |
| Projects list   | `/projects`          | PARTIAL  | Renders 3 projects with progress + invested; v2 spec uses a 2-col tile grid with hero photos + status pills, Flutter uses single-column cards. Not a user-stated complaint. |
| Financials      | `/financials`        | PASS     | Capital Account rows present (Committed ₹3.92 Cr / Received ₹0 / Pending ₹0). **No 5-year chart** — replaced by Risk vs Return scatter as designed. |
| Documents       | `/documents`         | PASS     | Common / My Projects / My Documents accordions render; "ARL Company Profile 2026.pdf" visible. |
| Activity        | `/activity`          | PASS     | "Notifications · 0 unread alerts" + History pill + empty-state copy. |
| Profile         | `/profile`           | PASS     | KYC / Bank / Documents in Account; Support section includes Assistance, Project Exit, Security, and the **Preview First-Payout Celebration** tile per spec. |
| Celebration     | `/celebration?…`     | PASS     | Confetti, "Your first payout has arrived" copy, "₹41,600 credited", **close X button top-right present**, View in Financials + Share your investment story CTAs + Maybe later link. |

## Defect Summary

| ID  | Screen           | Severity | Status                            |
|-----|------------------|----------|-----------------------------------|
| D-1 | Share Modal      | High     | **Resolved (2026-05-20)** — rebuild verified, modal opens with full preview + 3 CTAs |
| D-2 | Explore Detail   | Medium   | Open — spec deviation (Crop/Deadline tiles, Photos CTA, EAR layout). Not a user complaint. |
| D-3 | Projects list    | Low      | Open — list vs 2-col tile grid. Not a user complaint. |

## Files Touched

- `lib/features/projects/project_detail_screen.dart`
  - Added imports for `share_project_modal.dart` and
    `marketplace_project.dart`.
  - Added `_openShare(Project, InvestorUnit?)` helper.
  - Replaced placeholder SnackBar onPressed with the helper call.

No other Flutter sources, no pubspec, no asset additions.

## Verification Steps for the User

1. `cd C:\Users\Sahil\Downloads\ARL\arl_app`
2. `& C:\flutter\bin\flutter.bat build web --release`
3. Refresh `http://localhost:5000/` (hard reload — Ctrl+F5 — to evict
   the previous `main.dart.js`).
4. Open a project from the Projects tab → scroll to bottom → tap
   **Share Project**. The modal should slide up and show the 1080×1080
   preview card with hero photo, project name, 3 stat tiles, RM strip,
   and Share / Email / Copy link buttons.

If the modal still toasts the placeholder, the build didn't pick up
the diff — confirm `build/web/main.dart.js` was rewritten (check its
mtime).

## Final Verdict

🟡 **Yellow** — primary user complaints are all resolved in the
release build (Contract Progress bar, no Documents tile on Project
Detail, no Min Lock-in tile on Explore Detail, notification bell
states correct, 2 WhatsApp CTAs at top of Support, Celebration close
X present, no 5-year chart on Financials). One High-severity defect
(Share Modal) was a code-side stub that has been fixed this run and
needs a rebuild + retest to flip to Green. Two lower-priority
spec-deviation defects on Explore Detail and Projects list remain
open and are not part of the user's stated complaints.

### Update — 2026-05-20

🟢 **Green** — re-verified post-rebuild. Share Project modal now
opens correctly from Project Detail (full preview card + WhatsApp /
Email / Copy link CTAs + working close X). Spot-checks re-confirmed
during this pass: Contract Progress bar on Project Detail, clean
notification bell (no badge, 0 unread), both WhatsApp CTAs on
Support / Assistance, no Min Lock-in tile on Explore Detail
(Samsung LLP — Open for Reservation). The only remaining open items
are the two lower-priority spec deviations (D-2 Explore Detail
layout, D-3 Projects list grid) that are not user-stated complaints.
Cleared to ship.
