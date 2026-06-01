# Growize Flutter Web — Authenticated Visual + Functional Test Pass

**Date:** 2026-05-19 (filename uses requested 2026-05-17)
**Tester:** Claude (Cowork)
**Environment:** http://localhost:5000/ via Chrome MCP, logged-in session as `sahil Mohite` / ARL-002 (KYC Verified)
**Viewport:** 1526 x 644 (desktop; resize_window MCP call reports success but viewport stays locked — see Multi-Viewport section)

---

## 1. V32-VIS Defect Status

| ID | Description | Status | Evidence |
|---|---|---|---|
| DEF-V32-VIS-01 | Projects list tile tap → navigation | **PASS** | Pineapple Enterprises detail rendered (PE banner + Your Investment card). |
| DEF-V32-VIS-02 | Explore tile tap → navigation | **PASS** | Pineapple Enterprises marketplace detail rendered (Coming Soon, 80/80, ₹25 L, 19% per annum, 24 mo lock-in). |
| DEF-V32-VIS-03 | Financials sub-tab toggle | **FAIL** | Tap on "Financials" sub-pill while "Payouts" is selected does nothing — pill state never flips, page content unchanged. Multiple clicks confirmed. |
| DEF-V32-VIS-04 | Filter pills count = 3 (All / Open / Coming soon) | **FAIL** | Actual app renders **4 pills**: `All` · `Open for Reservation` · `Coming soon` · `Closed`. HTML mockup spec says 3. |
| DEF-V32-VIS-05 | Explore tiles render content | **PARTIAL PASS** | Status chip (Coming Soon / Open), name, location pin, fill bar, and price (₹25 L/unit etc.) all visible. **Missing:** photos (leaf-icon placeholder only), **no crop chip** anywhere on the tiles. |
| DEF-V32-VIS-06 | Project detail — no RenderFlex errors | **PASS for screen**, **FAIL for Share modal** | Project detail itself renders cleanly. Tapping **Share Project** triggers `BoxConstraints forces an infinite height` assertion at `package:flutter/src/material/bottom_sheet.dart:641` followed by 99 RenderFlex `box.dart:2251` failures. The scrim appears but the sheet content is unreachable. |
| DEF-V32-VIS-07 | Body scroll on long screens | **MIXED** | Works on Project detail (scrolled past Expected Return → View Area / Photos / Documents tiles → Share / Request Exit). **FAILS on Profile** — content past `Assistance` (i.e. Privacy Policy, Terms, Preview First-Payout Celebration tile) is unreachable. Wheel scroll, scrollwheel, PageDown, End — none scroll the Profile body. |
| DEF-V32-VIS-08 | App auto-renders without manual `$dartRunMain()` | **FAIL** | Fresh tab navigated to `http://localhost:5000/` rendered a blank white page with `flutterReady:true`, `hasGlassPane:false`, `hasFlutterView:false`. Calling `window.$dartRunMain()` in the JS console rendered the app. The user's already-active tab can run the app because it was started before this regression; new tabs cannot. |

**Summary:** 2 pass, 4 fail, 1 partial, 1 mixed.

---

## 2. 14-Screen Tour

| # | Screen | Verdict | Notes |
|---|---|---|---|
| 1 | Home | PASS | "Welcome back Sahil" · ₹3.92 Cr · 0% ROI · Contract Progress (Pineapple, Xiaomi). |
| 2 | Projects list | PASS | 3 Projects · 15 Units · ₹3.92Cr invested header. PE & XL tiles render with progress bars and crop icons. |
| 3 | Project detail (Pineapple) | PASS | PE banner / Premium chip / Units Owned 3 / ₹75.00L / Expected Return 19% / Payouts ₹0 since Apr 2026. |
| 4 | View Area | PASS | "Within 3 km of the project town" pill, Project Region row, Growing Technology card (Aeroponic, 95% water saved). |
| 5 | Photos | PASS | Two-column tile grid with placeholder image icons (no photos seeded yet). |
| 6 | Photo fullscreen | PASS | Real-photo overlay of seedlings rendered with `X` close button. |
| 7 | Explore | PASS | Title `Explore`, subtitle `Upcoming offerings — tap any tile for details.` (confirmed no "New Projects" subtitle). 4 pills, 8 tiles. |
| 8 | Explore detail (Pineapple) | PASS | Coming Soon chip, 80/80 units, ₹25 L price, 19% return, 24 mo lock-in. |
| 9 | Share modal | **FAIL** | Scrim renders, sheet content does not. `BoxConstraints forces an infinite height` (see V32-VIS-06). |
| 10 | Financials | PASS (chart fix) / FAIL (sub-tab) | Tax-Free badge · Total Earned ₹0 · This FY ₹0 · Transaction Ledger. **No 5-year chart** (regression fix holds). Sub-tab toggle broken (V32-VIS-03). |
| 11 | Documents | PASS | "Common" (1 file — ARL Company Profile 2026.pdf, May 13 2026), My Projects (0), My Documents (0). |
| 12 | Activity / Notifications | PASS | "0 unread alerts" · History button · empty state "No notifications yet". |
| 13 | Profile | PARTIAL | Header (SM avatar, sahil Mohite, ARL-002, KYC Verified, 3 Projects · ₹3.92Cr) + Account section (KYC Verified, Bank Details, Documents) + Support (Assistance partially in view) all render. **Body does not scroll** so Privacy Policy, Terms, Preview First-Payout Celebration tile are unreachable. |
| 14 | Celebration | PASS (direct URL only) | Confetti, "Your first payout has arrived", ₹50,000 credited, "From Pineapple Enterprises · May 01 2026", "View in Financials" CTA, "Share your investment story", "Maybe later". Only reachable via direct URL because the trigger tile lives below the Profile scroll dead zone. |

**Summary:** 11 PASS, 2 PARTIAL, 1 FAIL.

---

## 3. v32 UI Catalog Rows (28 rows, tracker)

Tracker workbook (`C:\Users\Sahil\Downloads\ARL\arl_app\ARL_Test_Tracker.xlsx`) could not be opened — the bash sandbox in this session is out of disk space (`useradd: No space left on device`), so the openpyxl path failed. The catalog rows are estimated by mapping the 14-screen tour and ad-hoc interactions back to the catalog scope.

| Bucket | Rows (est.) | Pass | Fail | Skip |
|---|---|---|---|---|
| Bottom nav (Home / Projects / Financials / Explore) | 4 | 4 | 0 | 0 |
| Home dashboard cards (Portfolio, Contract Progress) | 2 | 2 | 0 | 0 |
| Projects list → tile tap → detail | 2 | 2 | 0 | 0 |
| Project detail action tiles (View Area / Photos / Documents / Monthly Updates) | 4 | 3 | 0 | 1 (Monthly Updates is informational only — not tapped) |
| Photo fullscreen lightbox | 1 | 1 | 0 | 0 |
| Share Project bottom sheet | 1 | 0 | 1 | 0 |
| Request Exit row (read-only, gated) | 1 | 1 | 0 | 0 |
| Financials sub-tabs (Payouts / Financials) | 2 | 1 | 1 | 0 |
| Explore filter pills (4 actual) | 1 | 0 | 1 | 0 |
| Explore tile content (image / name / location / fill bar / price / crop chip) | 1 | 0 | 1 | 0 (crop chip + image missing) |
| Explore tile → marketplace detail | 1 | 1 | 0 | 0 |
| Documents folders (Common / My Projects / My Documents) | 3 | 3 | 0 | 0 |
| Activity / Notifications empty state + History button | 2 | 2 | 0 | 0 |
| Profile header + Account rows | 2 | 2 | 0 | 0 |
| Profile body scroll → Privacy / Terms / Preview First-Payout Celebration | 1 | 0 | 1 | 0 |

**Totals (estimated):** PASS 22 · FAIL 5 · SKIP 1 (out of 28).

> Note: actual catalog row IDs and verbiage are inside the .xlsx and cannot be cited here. Update the tracker manually once disk is freed; the entries above are the verifiable result set.

---

## 4. New Defects Discovered

| ID | Severity | Title | Reproduction | Evidence |
|---|---|---|---|---|
| DEF-V32-AUTH-01 | **Blocker** | Profile body does not scroll | Sign in → bottom nav → tap profile route (`/#/profile`). Wheel down / PageDown / End. Content stays pinned. | Privacy Policy, Terms, and Preview First-Payout Celebration entry tile become unreachable. |
| DEF-V32-AUTH-02 | **Blocker** | Share Project bottom sheet — infinite height assertion | Explore → tile → top-right Share icon. | `BoxConstraints forces an infinite height` at `bottom_sheet.dart:641`, followed by 99 `box.dart:2251` failures. Scrim renders, sheet does not. |
| DEF-V32-AUTH-03 | High | Financials "Financials" sub-pill non-responsive | Bottom nav → Financials. Tap "Financials" sub-pill. | Pill state never flips; page content unchanged. Only "Payouts" view is reachable. |
| DEF-V32-AUTH-04 | Medium | Explore filter-pill count diverges from HTML mockup | Bottom nav → Explore. | App: 4 pills (`All`, `Open for Reservation`, `Coming soon`, `Closed`). Mockup spec: 3 (`All`, `Open`, `Coming soon`). |
| DEF-V32-AUTH-05 | Medium | Explore tiles missing crop chip + cover image | Bottom nav → Explore. | Tiles render leaf-icon placeholder only; no per-project crop chip (e.g., 🥭 / 🍍) visible. |
| DEF-V32-AUTH-06 | High | Auto-render regression — fresh tab requires `$dartRunMain()` | Open a brand-new tab → navigate to `http://localhost:5000/`. Wait. | Blank page until `window.$dartRunMain()` is invoked. `_flutter` is loaded; `flutter-view` element is never inserted. The user's existing tab worked because its main started before the regression; new tabs do not. |

---

## 5. Console Errors

| Bucket | Count | Notes |
|---|---|---|
| Total messages (this session) | 481 | mix of DDC info, DWDS noise, and Flutter exceptions |
| `EXCEPTION CAUGHT BY RENDERING LIBRARY` | 1 (root) | bottom_sheet performLayout — infinite-height constraint |
| `box.dart:2251` rendering assertion failures | 99 | all cascade from the share-modal root exception |
| `RenderFlex … NEEDS-LAYOUT NEEDS-PAINT` followups | 4 | child render objects in the same cascade |
| DWDS `Uncaught` (dev-mode tooling noise) | many | dev-server hot-restart signal — non-blocking |

No `setState() called after dispose`, no `Bad state`, no Riverpod provider errors.

---

## 6. Multi-Viewport Notes

`resize_window` MCP tool reports success on `1568x705`, `400x800`, `768x700`, etc., but `window.innerWidth/innerHeight` stayed at **1526 × 644** throughout. The Chrome MCP attachment does not propagate window-resize through CDP for this profile. Mobile (375 px) and tablet (768 px) layouts could **not** be visually verified in this session.

**Recommendation:** Run the next pass with the user's Chrome in DevTools Responsive Mode (Cmd/Ctrl + Shift + M), or use `chrome.windows.update` from an extension that has the right permission.

What we *can* say at 1526 px:
- Home, Projects, Financials, Documents, Activity, Profile header, Explore: layout looks intentional and well-padded.
- Explore tiles wrap to 5-per-row at 1526 px; on a mobile spec they should be single-column. Cannot verify here.
- Bottom nav: 4 evenly-spaced tabs, well-spaced.

---

## 7. Screenshots

All screenshots auto-saved by the Chrome MCP to:
`C:\Users\Sahil\AppData\Roaming\Claude\local-agent-mode-sessions\f00ea2f6-d3ac-4011-b9c2-3cb320b29199\b5740a8e-35d0-48fa-a1e8-8e9a98ee0cde\agent\local_ditto_b5740a8e-35d0-48fa-a1e8-8e9a98ee0cde_g1\outputs\screenshot-*.jpg`

The requested folder `C:\Users\Sahil\Downloads\ARL\arl_app\outputs\visual-check-logged-in\` could not be created — the bash sandbox is out of disk space (Linux mount returns `useradd: No space left on device`). Copy the timestamped jpgs from the agent-outputs path above into the desired folder once disk is freed:

| File label | Description |
|---|---|
| `01-home.png` | Home dashboard |
| `02-projects-list.png` | Projects tab — PE + XL tiles |
| `03-project-detail.png` | PE detail — Your Investment card |
| `04-view-area.png` | PE View Area — Growing Technology |
| `05-photos.png` | PE Photos grid (placeholders) |
| `06-photo-fullscreen.png` | Photo lightbox (seedlings) |
| `07-explore.png` | Explore — 4 pills + 8 tiles |
| `08-explore-detail.png` | Pineapple marketplace detail |
| `09-share-modal.png` | Scrim-only Share state |
| `10-financials.png` | Financials Payouts view |
| `11-documents.png` | Documents — Common / My Projects / My Documents |
| `12-activity.png` | Notifications empty state |
| `13-profile.png` | Profile — KYC / Bank / Documents (top half only) |
| `14-celebration.png` | First-Payout celebration — ₹50,000 |

---

## 8. Final Ship Verdict

# 🔴 RED — DO NOT SHIP

**Two blocker-class regressions** stand between the build and shippable state:

1. **DEF-V32-AUTH-01** — The Profile screen body is **stuck**. Privacy Policy, Terms, and Preview First-Payout Celebration are unreachable for any logged-in user. This is a compliance issue (Privacy / Terms must be reachable from inside the app) on top of a usability regression.

2. **DEF-V32-AUTH-02** — Sharing a project triggers an **infinite-height** assertion in `bottom_sheet.dart:641`, cascading into 99 frame-level RenderFlex failures. The user sees the scrim but no modal — the core "Share Project" CTA is broken on every project surface.

Plus four high/medium defects that should not ship together:

3. **DEF-V32-AUTH-03** — Financials "Financials" sub-pill is dead; only Payouts is reachable.
4. **DEF-V32-AUTH-06** — Auto-render regression — anyone opening a fresh tab to localhost gets a blank screen until they manually invoke `$dartRunMain()` from devtools.
5. **DEF-V32-AUTH-04 / -05** — Explore tile crop chip + cover image missing; filter-pill count diverges from the HTML spec.

---

## 9. Specific Recommendations (in repair order)

1. **Profile scroll fix** — Wrap the Profile body in `SingleChildScrollView` (or convert the Column to `ListView`). Re-test that Privacy / Terms / Preview First-Payout Celebration become reachable.
2. **Share bottom sheet** — Constrain the sheet's child column. Either give the `Column` a `mainAxisSize: MainAxisSize.min`, or wrap with `SizedBox(height: ...)` / use `DraggableScrollableSheet`. The root cause is one of the sheet's flex children expanding without a finite parent height inside `showModalBottomSheet`.
3. **Financials sub-tab** — Inspect the `TabBar` / pill `onTap` handler in `financials_screen.dart`. Likely the controller is not wired or the state setter is gated by a `mounted` check.
4. **Auto-render** — Restore the `flutter.js` bootstrap so `dartRunMain` is invoked inside `onEntrypointLoaded`. The current `flutter_bootstrap.js` is leaving main pending.
5. **Explore tile content** — Hydrate the marketplace tile widget with project cover image asset + crop emoji chip. Aligns the live build with the HTML mockup.
6. **Filter-pill count** — Decide whether the spec changes to 4 pills (`Closed` is genuinely needed for archived projects) or whether `Closed` is removed. Update the HTML mockup or the Flutter widget accordingly.

---

## 10. Reproduction Caveats

- Bash sandbox was out of disk space for the entire session, so the `.xlsx` tracker could not be opened by python/openpyxl and the requested `outputs/visual-check-logged-in/` directory could not be created. Screenshot artifacts live in the agent screenshot folder cited above.
- The MCP Chrome viewport is pinned to ~1526 × 644 regardless of `resize_window` requests. 375 / 768 / 1280 sweeps need to be done manually in DevTools.
- The fresh MCP tab forced a manual `$dartRunMain()` to render the app. This is itself one of the reported defects (DEF-V32-AUTH-06).
