# Growize v32 Visual Check — 2026-05-18

Visual verification run against the live Flutter web app vs the HTML mockup
`Growize App Design v2 (proposed).html`. This complements the static code-review
pass (`PASS-CR` baseline) recorded in `ARL_Test_Tracker.xlsx > v32 UI Catalog`.

## Connection & boot state

- **Target**: `http://localhost:5500/` (static-file server; not `flutter run`)
- **Build mode**: dev (DDC), CanvasKit renderer, 1121 DDC modules loaded
- **Auth state**: Pre-existing Supabase session in browser; logged in as `sahil Mohite` (ARL-002, KYC Verified)
- **Viewport**: 1526 x 644 logical (1568 x 662 physical, DPR 1.25). Window resize
  to mobile width was attempted but the rendered viewport did not change.
- **Initial boot defect**: Flutter Web auto-bootstrap did not run main() - DDC
  loaded 1121 modules but `flutter-view` / `flt-glass-pane` were never created
  and no scene was rendered. The app only became visible after
  `window.$dartRunMain()` was invoked manually via DevTools. Root cause: the
  served `index.html` still contains the literal placeholder
  `<base href="$FLUTTER_BASE_HREF">`, indicating the file is being served raw
  from `web/` (or a stale build) rather than from a Flutter-substituted output.
  Logged as **DEF-V32-VIS-08** below.

## Headline counts (28 v32 catalog rows)

| Status         | Count |
| -------------- | ----- |
| **PASS**       | 7     |
| **PARTIAL**    | 2     |
| **FAIL**       | 4     |
| **SKIP-BLOCKED** | 15  |
| Total          | 28    |

(SKIP-BLOCKED dominates because tile-tap navigation is broken at the viewport
the desktop browser exposes - see DEF-V32-VIS-01/02/03/06/07 below.)

## Screens captured

Saved under `outputs/visual-check-v32/`:

| File                       | Screen                                    | URL                                                |
| -------------------------- | ----------------------------------------- | -------------------------------------------------- |
| 01-home.jpg                | Home (top, hero stats)                    | `/#/`                                              |
| 01b-home-scrolled.jpg      | Home (Contract Progress + Active Units)   | `/#/`                                              |
| 02-projects-list.jpg       | Projects list (Xiaomi, Samsung visible)   | `/#/projects`                                      |
| 05-photos.jpg              | Photos / Gallery empty state              | `/#/gallery`                                       |
| 07-explore.jpg             | Explore tab (2-col, COMING SOON tiles)    | `/#/explore`                                       |
| 10-financials.jpg          | Financials > Payouts                      | `/#/financials`                                    |
| 11-documents.jpg           | Documents (ARL Company Profile 2026.pdf)  | `/#/documents`                                     |
| 12-activity.jpg            | Activity / Notifications empty state      | `/#/activity`                                      |
| 13-profile.jpg             | Profile (top, account section)            | `/#/profile`                                       |
| 14-celebration.jpg         | First-payout celebration overlay          | `/#/celebration?amount=125000&project=Xiaomi+LLP&date=2026-05-15` |

Screens NOT captured (root causes recorded in defects):

- Project detail (`/projects/<id>`) - tile-tap broken; direct nav with guessed
  id renders the "Project not found" empty state correctly, indicating the
  route resolves but data fetch fails for unknown ids.
- Project View Area, per-project Photos - only reachable from project detail.
- Photo fullscreen - Photos feed is empty.
- Explore detail, Share Project modal - tile-tap broken on Explore tiles too.
- Marketplace stats grid - depends on Explore detail.
- Risk vs Return chart (Financials > Financials sub-tab) - sub-tab tap broken.
- Profile lower section incl. Preview First-Payout Celebration tile - page
  scroll broken at desktop width.

## Defects (DEF-V32-VIS-NN)

### DEF-V32-VIS-01 - Projects list tile tap does not navigate (BLOCKER)

Tapping a Projects list card (anywhere on the row, on the "View ->" affordance,
or on the project name) does not navigate. URL stays at `/#/projects`. No
visual ripple, no error.

Earlier in the session, the same tap at a slightly different viewport size
(1526x644 unscaled) threw a cascade of `RenderFlex` overflow + "Cannot hit
test a render box with no size" exceptions, indicating the project detail
screen attempts to render but has zero-width children that crash hit-testing.

Suggested fix: audit `project_detail_screen.dart` and `ProjectActionTiles` for
unconstrained Row/Column children at viewport widths > the mobile target. Add
`Expanded`/`Flexible` wrappers or constrain via `LayoutBuilder`. Reproduces
deterministically once `$dartRunMain` has been kicked.

### DEF-V32-VIS-02 - Explore tile tap does not navigate (BLOCKER)

Same pattern as DEF-V32-VIS-01 on Explore tiles. URL stays `/#/explore`. No
error. Likely the same Row/Column constraint issue manifesting on
`explore_detail_screen.dart`.

### DEF-V32-VIS-03 - Financials sub-tab toggle does not respond

Clicking the "Financials" pill in the Financials screen sub-tab row does not
switch the body. "Payouts" remains active, "Financials" stays inactive.
Suspect onTap is being swallowed by an overlapping gesture detector or the
chip is rendering without an Ink/InkWell.

### DEF-V32-VIS-04 - Explore filter pills missing "Closed" option

Mockup specifies 4 pills: All, Open for Reservation, Coming Soon, **Closed**.
The Flutter app renders only 3 (the first three). The "Closed" pill is
missing entirely. `explore_screen.dart:51` area likely under-populates the
pill list, or `MarketplaceProjectStatus.closed` is filtered out.

### DEF-V32-VIS-05 - Explore tile content not rendering (HIGH)

Each Explore tile is essentially blank - only the "COMING SOON" badge in the
top-left and a faint leaf icon mid-tile. **Missing**:

- Project image (background)
- Project name (h-text)
- Location row with map pin
- Crop chip (e.g. "Tomatoes")
- Fill bar with color ramp (accent / gold / earth)
- "X / Y units · Z available" caption
- Price label "Rs 25 L /unit"

Backend appears to be returning only `status` (and maybe an image URL). Either
the data layer is mis-mapped, the templates are guarded by null checks that
all silently swallow, or images are blocked and the rest of the layout
collapses behind them.

### DEF-V32-VIS-06 - Project detail crashes/blanks at desktop width

Tapping a Projects list card at 1526-px viewport produced ~60 `RenderFlex`
exceptions in `box.dart:2251` (assertion failures) and several "Cannot hit
test a render box with no size" errors, after which the body went blank.
Resizing to a smaller window mitigated the crash but the tap then becomes a
no-op (DEF-V32-VIS-01). Indicates the project-detail subtree is fragile at
wider widths - needs a responsive constraints audit.

### DEF-V32-VIS-07 - Body scroll unresponsive

`wheel`, `PageDown`, drag-scroll, and JS-dispatched WheelEvents against
`flutter-view`, `flt-glass-pane`, body, and window all failed to scroll any
page (Profile, Home post-state). Mouse-wheel must reach the underlying
`Scrollable` somehow, but the dev build observed here does not respond
under automation. Any content below the fold (e.g. Profile > Preview
Celebration, Profile > Replay Tour absence, Home > Active Units) cannot be
exercised by a non-touch user, which would be a real accessibility/usability
regression if reproducible outside automation.

### DEF-V32-VIS-08 - Flutter bootstrap does not auto-run main()

Loading `http://localhost:5500/` rendered a blank page indefinitely. The
boot completed all 1121 DDC module loads, `window.$dartRunMain` was a
defined function, but it was never invoked. Manually calling
`window.$dartRunMain()` started the app correctly. Root cause appears to be
the served `index.html` containing the unsubstituted placeholder
`<base href="$FLUTTER_BASE_HREF">`, which suggests this is `web/index.html`
served by a generic static-file server (port 5500 is the VS Code Live Server
default) rather than the output of `flutter run` / `flutter build web`.

Suggested fix: ship a tiny `make-dev-host.sh` that runs
`flutter build web --pwa-strategy=none --release=false` and serves the
resulting `build/web/` directory, OR document that QA must use
`flutter run -d chrome --web-port=5500` directly so the dev tools rewrite the
base href.

## Per-screen observations against the mockup

### Home (`/#/`)
- PASS: Hero "WELCOME BACK / Sahil" left, "All Projects" location dropdown right
- PASS: Portfolio card - Total Portfolio Value Rs 3.92 Cr, Invested Rs 3.92Cr, Returns +Rs 0,
  0% Annual ROI, "Outperforming vs 12% Nifty" pill
- PASS: Contract Progress lists 3 LLPs (Xiaomi 0% Month 0/60, Samsung 0% Month 0/60,
  Pineapple Enterprises 0% Month 4/60) with "View All Projects ->" button
- PASS: Active Units card: "15 Units · 3 Projects"
- NOTE: Bottom nav shows 4 items only (Home, Projects, Financials, Explore). Profile is
  reachable via the top-right SM avatar (not bottom nav).

### Projects (`/#/projects`)
- PASS: Header "YOUR PORTFOLIO / All Projects" and meta "3 Projects · 15 Units · Rs 3.92Cr invested"
- PASS: Two cards visible: Xiaomi LLP (Bengaluru, Karnataka, 7 units, Rs 1.93Cr) and
  Samsung LLP (Pune, Maharashtra, 5 units, Rs 1.25Cr); both Pending, both Contract Progress 0%
- FAIL: Tapping a card does nothing (DEF-V32-VIS-01)
- NOTE: Third project (Pineapple Enterprises) not visible without scroll; scroll unverifiable (DEF-V32-VIS-07)

### Explore (`/#/explore`)
- PASS: "Upcoming offerings - tap any tile for details." (matches mockup, no "New Projects")
- PASS: 2-column grid layout
- FAIL: Only 3 filter pills (missing "Closed", DEF-V32-VIS-04)
- FAIL: Tile content empty - no image / name / location / crop / fill bar / price (DEF-V32-VIS-05)
- FAIL: Tile tap doesn't navigate (DEF-V32-VIS-02)

### Financials (`/#/financials`)
- PASS: Page title "Financials", "All Projects" filter
- PASS: Sub-tabs "Payouts" (active) and "Financials"
- PASS: Tax-Free under Sec 10(2A) info pill
- PASS: Total Earned Rs 0 (Since inception) + This FY Rs 0 (FY 2026-27) cards
- PASS: "Transaction Ledger" heading (empty body)
- FAIL: Cannot switch to "Financials" sub-tab (DEF-V32-VIS-03), so Risk vs Return
  chart and absence-of-5-year-chart in that view both unverified
- PASS: No 5-year chart visible on Payouts view <- matches spec

### Documents (`/#/documents`)
- PASS: Back arrow + "Documents" title
- PASS: Common (1 file) -> "ARL Company Profile 2026.pdf · May 13, 2026" with eye icon
- PASS: My Projects (0 files) collapsed
- PASS: My Documents (0 files) collapsed

### Activity (`/#/activity`)
- PASS: "Notifications / 0 unread alerts" header, History pill top-right
- PASS: Empty state: bell icon + "No notifications yet" + "Payout and operational alerts will appear here as your projects update."

### Profile (`/#/profile`)
- PASS: Avatar + "sahil Mohite", ARL-002, KYC Verified, "3 Projects · Rs 3.92Cr invested"
- PASS: Active Projects card lists all three: "Xiaomi LLP · Samsung LLP · Pineapple Enterprises"
- PASS: Account section: KYC Details (Verified), Bank Details, Documents tiles
- NOTE: Support section begins ("Assistance" tile partially visible) but rest of the
  Profile is unreachable due to scroll defect (DEF-V32-VIS-07). Preview First-Payout
  Celebration tile, Replay Tour absence, and any other settings cannot be confirmed visually.

### Photos / Gallery (`/#/gallery`)
- PASS: Header "Photos / Daily 9:00 AM IST · Last 30 days" with back arrow, dark teal background
- PASS: Empty state: image icon + "No photos yet" + "Daily photos appear here once your project is operational."

### Celebration (`/#/celebration?amount=...&project=...&date=...`)
- PASS: Confetti / sparkle background animation
- PASS: "Your first payout has arrived"
- PASS: Headline "Rs 1.25L credited" in accent green (test payload was amount=125000)
- PASS: "From Xiaomi LLP · May 15, 2026"
- PASS: Primary CTA "View in Financials" (filled gradient green)
- PASS: Secondary CTA "Share your investment story" (outlined)
- PASS: "Maybe later" text link

## Console errors observed

- During the broken project-detail tap (pre-resize): ~60 messages including
  one `EXCEPTION CAUGHT BY RENDERING LIBRARY`, multiple
  `RenderFlex#...` overflow/relayout-boundary errors,
  many `Assertion failed: ...box.dart:2251:12`,
  several `Cannot hit test a render box with no size`,
  and `Assertion failed: ...mouse_tracker.dart:199:12`.
- Otherwise the console is clean - only DDC bootstrap INFO logs, Supabase
  init / refresh-session INFO, and `[trackedFetch] OK in ...ms` traces.

## Tracker changes

- Backup written to `outputs/ARL_Test_Tracker_pre_visual_check_v2.xlsx`.
- `v32 UI Catalog` sheet updated: 28 rows re-graded from `PASS-CR` to:
  7 x PASS, 2 x PARTIAL, 4 x FAIL, 15 x SKIP-BLOCKED. Notes column
  populated with screenshot references for each row.

## Final visual ship verdict

**RED**

The two highest-impact user paths - opening a project from the list and
opening an Explore listing - are both broken. Add to that an Explore grid
that renders without any of its tile content and a hard scrolling regression,
and the build is not shippable from a visual / UX standpoint as-observed.

Recommended next steps before re-test:

1. Investigate the index.html / dev-server setup (DEF-V32-VIS-08) - confirm
   whether subsequent QA passes should run under `flutter run` rather than
   live-server, since the manual `$dartRunMain` workaround is not realistic
   for actual investors.
2. Fix Project detail responsive layout (DEF-V32-VIS-06) - start with the
   RenderFlex causing the assertions at line `box.dart:2251`.
3. Once project detail and Explore detail open, re-run the visual sweep to
   convert the SKIP-BLOCKED rows.
4. Add the missing "Closed" filter pill and debug why Explore tile children
   are not rendering (DEF-V32-VIS-04 / 05).
