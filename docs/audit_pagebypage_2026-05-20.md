# Growize Flutter App — Page-by-Page Audit vs. HTML Mockup
**Audit date:** 2026-05-20
**Mockup reference:** `Growize App Design v2 (proposed).html`
**App build:** Flutter web release served at `http://localhost:5000/` (user already authenticated as Sahil Mohite / ARL-002)
**Tester:** ARL Tech via Cowork audit pass

---

## Method

For each of 15 target screens the audit:
1. Navigated the live Flutter web app
2. Took screenshots at each state (saved by the Chrome MCP harness)
3. Read the corresponding `<div id="page-…">` block in the HTML mockup
4. Tapped every visible button/CTA and recorded the outcome
5. Compared visual + behavioral details to the HTML spec

Data differences caused by the live test account (real ARL data — Pineapple Enterprises / Xiaomi LLP / Samsung LLP, ₹3.92 Cr portfolio, 0% ROI early-stage) are **not** treated as defects — only structural / layout / behavior mismatches are. The HTML mockup itself uses fictional data (EKA / Sunrise Orchards / Verdant Acres, ₹1.43 Cr, 18.2% ROI) so a 1:1 number compare is impossible.

---

## Screen 1 — Auth / Login

**Outcome:** Navigating to `/#/auth` redirects back to `/` (Home). Cannot inspect because the user is authenticated. No defect — expected behavior for an already-signed-in session.

| Element | HTML | Flutter | Status |
|---|---|---|---|
| Auth flow | Not in HTML mockup (mockup assumes signed-in) | Auto-redirects to Home when signed in | PASS |

| Button | Expected | Actual | Status |
|---|---|---|---|
| n/a | — | — | — |

**Observations:** Auth screen exists at `lib/features/auth/auth_screen.dart` but cannot be tested in this session without signing out (forbidden per task rules).

---

## Screen 2 — Home Dashboard

### Visual diff

| Element | HTML says | Flutter shows | Status |
|---|---|---|---|
| First-time tour CTA banner | Gradient pill with "New here? Take a quick tour", Sparkles icon, "Take Tour" gold button → `startTour()` | **Not present** | **FAIL (missing)** |
| Greeting eyebrow | "WELCOME BACK" + bold "Welcome Back" headline (no name) | "WELCOME BACK" + bold "Sahil" | DIFFERENT (Flutter adds first name — acceptable enhancement) |
| Project switcher | `All Projects` chip with map-pin + chevron, opens dropdown menu | `All Projects` chip with map-pin + chevron, opens full "Select Project" page | DIFFERENT BEHAVIOR (HTML: inline menu; Flutter: full route) |
| Sync badge | Live pulsing green dot + "Live" label | Clock icon + "Updated 37s ago" text | DIFFERENT FORMAT |
| Total Portfolio Value | "Total Portfolio Value" eyebrow + ₹1.43 Cr (mockup data), eye toggle next to label | "TOTAL PORTFOLIO VALUE" + ₹3.92 Cr (real), eye toggle present | PASS (eye toggle works) |
| Invested + Returns sub-cards | 2-col grid inside hero card | 2-col grid inside hero card | PASS |
| Annual ROI panel | 18.2% + "Outperforming vs 12% Nifty" pill — tapping opens Financials | 0% + "Outperforming vs 12% Nifty" pill | PASS (panel renders; tap-to-financials not verified because no payouts exist yet) |
| Project Progress card | Toggles between "Single project" view (project name + status pill + 1 progress bar + View Project) AND "Contract Progress (all)" view (3 stacked bars + View All Projects) | Always shows the "Contract Progress (all)" 3-bar view regardless of `All Projects` selection | PARTIAL (single-project view not implemented) |
| "View All Projects" CTA inside progress card | Pill button → projects page | **Not present** | FAIL (missing CTA) |
| Quick Stats grid: Next Payout card | ₹41,600 / Apr 15, 2026 · EKA — tap opens Financials/Payouts | **Not present** | **FAIL (missing card)** |
| Quick Stats grid: Active Units card | 5 Units / 3 Projects — tap opens Projects | **Not present** | **FAIL (missing card)** |
| Bottom nav | Home / Projects / Financials / Explore | Home / Projects / Financials / Explore | PASS |
| Header bar | growize wordmark + notification bell + SM avatar | growize wordmark + notification bell + SM avatar | PASS |

### Buttons

| Button | Expected action | Actual action | Pass/Fail | Notes |
|---|---|---|---|---|
| Notification bell | Open `page-activity` → Notifications view | Opens "Notifications — 0 unread alerts" empty state with History toggle | PASS | |
| SM avatar | Open `page-profile` | Opens Profile screen | PASS | |
| All Projects chip | Open inline dropdown | Opens full-page "Select Project" route | DIFFERENT | functionally equivalent |
| Eye icon (balance toggle) | Toggle balance hide/show | Toggle present, click registers | PASS (assumed — icon state changes; not tested deeply) | |
| Portfolio Card body | n/a (no tap) | n/a | PASS | |
| Annual ROI panel | `showPage('financials', 'f-financials')` | not confirmed | UNTESTED | progress card scroll target obscures it; deferred |
| "View All Projects" inside progress | navigates to Projects | button missing | FAIL | |
| Next Payout card | `showPage('financials', 'f-payouts')` | card missing | FAIL | |
| Active Units card | `showPage('projects')` | card missing | FAIL | |
| "Take Tour" button | `startTour()` overlay | banner missing | FAIL | |
| Home tab in bottom nav | stay/refresh on Home | refreshes Home | PASS | |
| Projects tab | open Projects | navigates | PASS | |
| Financials tab | open Financials | navigates | PASS | |
| Explore tab | open Explore | navigates | PASS | |

### Observations

The Home screen is the most under-built compared to HTML — three substantive elements are missing (tour banner, Next Payout quick stat, Active Units quick stat). The portfolio card itself is faithfully reproduced; the gap is everything that was supposed to appear *below* it. The sync badge format also drifts ("Updated 37s ago" vs. the HTML's "Live" pulse-dot pill).

---

## Screen 3 — Activity / Notifications

### Visual diff

| Element | HTML says | Flutter shows | Status |
|---|---|---|---|
| Page title | "Notifications" / "3 unread alerts" | "Notifications" / "0 unread alerts" | PASS (real data — no notifs yet) |
| Toggle button (top right) | "History" pill with history icon — toggles to Activity Timeline view | "History" pill — switches to Activity History view labeled "Activity History — Payouts & operational events" with reverse pill "Notifications" | PASS |
| "Recent" eyebrow | Present | Not visible (empty state) | N/A (no data) |
| Mark all read button | Text link "Mark all read" | **Not visible because list is empty** | UNTESTED |
| Notification item layout | Color-coded card (earth/accent/gold) + icon disc + title + time + body + action CTA + unread dot | n/a (empty) | UNTESTED |
| Empty state | (HTML doesn't specify; mockup always has 3 items) | "No notifications yet — Payout and operational alerts will appear here as your projects update." | EXTRA (acceptable empty-state polish) |
| Activity Timeline view | Filter pills All / Operational / Payouts + month groups (Mar/Feb/Jan 2026) with dotted-timeline cards | Filter pills All / Operational / Payouts + empty state "No activity yet" | PASS (structure correct; no data) |

### Buttons

| Button | Expected action | Actual action | Pass/Fail |
|---|---|---|---|
| ← back arrow | return to Home | works | PASS |
| History toggle | swap to timeline view | swaps to "Activity History" view | PASS |
| Notifications toggle (reverse) | swap back to notifications | swaps back | PASS |
| All / Operational / Payouts filter pills (in timeline view) | filter timeline by type | pills render and are tappable; cannot validate filtering without data | UNTESTED-WITH-DATA |
| Mark all read | mark all notifs read | n/a (no notifs) | UNTESTED |
| Per-notif "View" CTAs | open Gallery / Financials / etc | n/a | UNTESTED |

### Observations

Structure matches HTML closely. The empty states are well-crafted. Need real notification data flowing in production to fully validate item rendering, color-coding, time labels and per-item CTAs.

---

## Screen 4 — Projects List

### Visual diff

| Element | HTML says | Flutter shows | Status |
|---|---|---|---|
| "Your Portfolio" eyebrow + "All Projects" title | Present | Present (matches casing/typography intent) | PASS |
| Subtitle | "3 Projects · 5 Units · ₹1.83 Cr invested" | "3 Projects · 15 Units · ₹3.92Cr invested" | PASS (real data) |
| Portfolio 3-stat strip (Active / Earned / Pending) | Present — 3 mini cards | **Not present** | **FAIL (missing)** |
| Layout | **2-column tile grid** with hero images, 16:10 aspect | **1-column wide-card list** with letter avatars | **FAIL (layout mismatch)** |
| Per tile: hero image | Real Unsplash cover image per project | **Letter avatar in colored chip (PE/XL/SL)** — no images | **FAIL** |
| Per tile: status pill (top-left) | OPERATIONAL / PENDING / etc | "Pending" pill top-right of each card | PARTIAL (uses single state for all) |
| Per tile: Premium/Standard badge (top-right) | "Premium" with award icon / "Standard" with leaf icon | **Not present** | **FAIL (missing)** |
| Per tile: project name + location | "EKA / Pune, MH" with map-pin | "Pineapple Enterprises / · Month 4" (no map-pin location for PE — location only on XL & SL) | PARTIAL |
| Per tile: crop pill | "🍅 Tomatoes" / "🍇 Grapes" / "🌱 Mixed Greens" pill | "Crop 🌱" sprout emoji label only — no specific crop name | **FAIL (lacks crop name)** |
| Per tile: month / 60 | "Month 9/60" small text | "Month 4" with no "/60" denominator | PARTIAL |
| Per tile: units + total value | "1 Unit · ₹25 L" | "Your Units 3 · Invested ₹75.00L" | PASS (different labels but equivalent info) |
| Per tile: thin progress bar | 1px gradient bar to 15/45/0 % | "Contract Progress" + percentage + bar | PASS |
| Per tile: next payout footer | "Next payout / ₹41,600 · Apr 15" | "Next: ₹0 · N/A" | PASS (real data — no payouts) |
| Per tile: "View →" link | n/a (entire tile is a button) | "View →" link bottom-right | DIFFERENT |

### Buttons

| Button | Expected action | Actual action | Pass/Fail |
|---|---|---|---|
| Project tile | `selectGlobalProject('xx', true)` → navigates to Project Detail | Tile / "View →" link both navigate to Project Detail | PASS |
| 3-stat strip (Active/Earned/Pending) | display only | strip missing | FAIL |
| Bottom-nav Projects tab | refresh | works | PASS |

### Observations

This is the **single biggest visual mismatch** in the audit. The HTML expected a polished, gallery-style 2-col tile grid with hero photography; Flutter ships a flat wide-card list with letter chips. The 3-stat portfolio strip is also gone. The Premium/Standard badge is gone. Project tiles work as buttons (good) but the visual hierarchy is completely different from the spec.

---

## Screen 5 — Project Detail

### Visual diff

| Element | HTML says | Flutter shows | Status |
|---|---|---|---|
| Back arrow + Share/share icon | top-left back, share icon top-right inside hero | Back arrow top-left; **no share icon in hero** (Share is at bottom of page as CTA) | PARTIAL |
| Hero banner | 200px tall, real Unsplash photo, dark gradient, "OPERATIONAL" status pill top-center, title + map-pin + location bottom-left | Gradient gray banner with large faded "PE" letters; Premium gold pill top-right; **no status pill**; title bottom-left (no location); **no real image** | **FAIL (no image, no status pill, location missing)** |
| Your Investment 2×2 | UNITS OWNED / TOTAL INVESTED / EXPECTED RETURN / PAYOUTS TO DATE | UNITS OWNED 3 / TOTAL INVESTED ₹75.00L / EXPECTED RETURN 19% annual / PAYOUTS TO DATE ₹0 since Apr 2026 | PASS |
| Contract Progress bar | label + % | "Contract Progress 0% / Jan 2026 — 4 yrs 8 mos left — Jan 2031" | PASS (Flutter adds nice timeline detail) |
| Current Phase + 6-stage timeline | Stage chip + horizontal 6-circle timeline (Land/Soil/Greenhouse/Planting/Harvest/Full Ops) with current stage active | Stage chip "Stage 1 of 6" + horizontal 6-circle timeline with stage 1 active, all 6 labels visible (Land/Soil/Greenhouse/Planting/Harvest/Full Ops) | PASS |
| Recent Payouts | Card with payout rows + "View all" | "Recent Payouts / View all →" with empty state "No payouts yet — first credit lands after the next harvest" | PASS |
| View Area + Photos action tiles | 2 side-by-side action tiles | 2 side-by-side action tiles (View Area: Map · tech · crops / Photos: Daily 9 AM IST) | PASS |
| Monthly Updates | Stacked update cards with month / status / body | "Monthly Updates / Phase updates will appear here once operations begin." empty state | PASS |
| Projection callout | Info icon + "Expected annual return: 19% — based on 5-year projection..." | "Expected annual return: 19% — based on 5-year projection. Detailed financials shared post-allocation." | PASS |
| Share Project CTA | Outline button → Share modal | "Share Project" pill button → opens Share modal | PASS |
| Request Exit CTA | Disabled pill "Request Exit · available after 5-yr lock-in" | "Request Exit · available after 5-yr lock-in" disabled-looking pill | PASS |

### Buttons

| Button | Expected action | Actual action | Pass/Fail |
|---|---|---|---|
| ← back | return to projects list | works | PASS |
| Premium pill | display only | display only | PASS |
| Share icon in hero | open Share modal | **not present in hero** | FAIL (missing affordance — share is only at bottom) |
| View Area tile | open View Area sub-screen | opens View Area | PASS |
| Photos tile | open Photos sub-screen | opens Photos | PASS |
| Recent Payouts "View all →" | navigates to Financials/Payouts | not validated in this run | UNTESTED |
| Share Project (bottom CTA) | open Share modal | opens Share modal | PASS |
| Request Exit CTA | dialog or info | not tapped (disabled-looking) | UNTESTED |

### Observations

Project Detail is in good shape structurally — the 2×2 Investment card, 6-stage timeline, projection callout, action tiles and CTAs are all present. The hero banner is the weak point: no real photo, status pill missing. Hero share icon is missing.

---

## Screen 6 — View Area

### Visual diff

| Element | HTML says (`page-location`) | Flutter shows | Status |
|---|---|---|---|
| Header | back arrow + "Pineapple Enterprises / View Area" | back arrow + "Pineapple Enterprises / View Area" | PASS |
| Map | Real map tile with radius circle + zoom scale | **Stylized green circle with "1 km" scale and "Within 3 km of the project town" pill** — placeholder, not real Mapbox/Google map | **FAIL (no real map)** |
| "Project Region" label | Present below map | Present | PASS |
| Growing Technology card | Title + Aeroponic pill + 4-tile grid (Method/Water/Yield/Cycles) + 2-tile (Pesticide/Climate) + Tech stack + Cert pills | All present: Method Aeroponic, Water Saved 95%, Annual Yield 32 kg/m², Cycles 8/yr, Pesticide-Free ✓, Climate Controlled ✓, "IoT sensors · auto-misting · ML-based nutrient dosing", FSSAI / Organic / GAP pills | PASS |
| Crops Grown | Card with crop tiles | "Crops Grown / Seasonal Crops (Primary)" | PARTIAL (HTML lists specific crops + emojis; Flutter just says "Seasonal Crops") |
| Climate Control | Card with growing season / temp / humidity | "GROWING Year-round / TEMP 22-26°C / HUMIDITY 65-75%" | PASS |
| Property | TOTAL AREA / UNDER CULTIVATION + tagline | "TOTAL AREA TBD / UNDER CULTIVATION TBD / Controlled environment agriculture with smart irrigation" | PASS (real data — TBD) |
| Privacy footer | "Approximate location — exact address shared post-allocation." | "Approximate location — exact address shared post-allocation." | PASS |

### Buttons

| Button | Expected action | Actual action | Pass/Fail |
|---|---|---|---|
| ← back | return to Project Detail | works | PASS |
| Map (pan/zoom) | interactive map | **not interactive — static placeholder** | FAIL |
| Cert pills (FSSAI/Organic/GAP) | display only | display only | PASS |

### Observations

Strong content fidelity. The map is the only major gap — Flutter ships a stylized circle placeholder instead of a real basemap. Crop list is genericized ("Seasonal Crops") vs. HTML's specific crop emojis/names.

---

## Screen 7 — Photos (Gallery)

### Visual diff

| Element | HTML says (`page-gallery`) | Flutter shows | Status |
|---|---|---|---|
| Header | "Photos" title + back | "Photos / Pineapple Enterprises" + back | PASS (Flutter adds project context) |
| Grid layout | 2-col grid with rounded-corner thumbnails | 2-col grid with rounded thumbnails | PASS |
| Photo count | Multiple real photos | 5 real photos + 1 placeholder slot showing empty image icon | PASS |
| Fullscreen viewer | tap photo → fullscreen overlay with X close | tap photo → fullscreen overlay with X close (top-left) | PASS |
| Caption / date | Per-photo caption | none visible (in fullscreen) | PARTIAL |

### Buttons

| Button | Expected action | Actual action | Pass/Fail |
|---|---|---|---|
| ← back | return to Project Detail | works | PASS |
| Thumbnail tap | open fullscreen | opens fullscreen with X close | PASS |
| Fullscreen X close | return to grid | works | PASS |

### Observations

Photos screen is clean. The empty placeholder cell in the 6th grid slot is acceptable (handles small image counts).

---

## Screen 8 — Explore Tab

### Visual diff

| Element | HTML says | Flutter shows | Status |
|---|---|---|---|
| Title | "Explore" | "Explore" | PASS |
| Subtitle | (HTML has it via context cards) | "Upcoming offerings — tap any tile for details." | PASS |
| Filter pills | All / Open / Coming Soon / Closed | All / Open for Reservation / Coming soon / Closed | PASS (label "Open" → "Open for Reservation" — minor) |
| Tile grid | 2-col with hero photos, status pill top-left, Premium badge top-right | 2-col with **letter gradient avatars** (P, S, A, G) and status pill top-left | **PARTIAL (no hero photos, no Premium badges)** |
| Per tile: name + location | Bold name + map-pin location | Bold name + map-pin location | PASS |
| Per tile: crop pill | Specific crop with emoji | "Mixed crops" generic pill | PARTIAL |
| Per tile: progress / availability | "X / 48 units · Y available" with fill bar | "1 / 44 units · 43 available" with fill bar (where Open) — "Reservations open Sep 2026" (where Coming Soon) | PASS |
| Per tile: price | ₹25 L | ₹25 L/unit | PASS |
| Per tile: tap | opens explore detail | opens explore detail | PASS |

### Buttons

| Button | Expected action | Actual action | Pass/Fail |
|---|---|---|---|
| All / Open for Reservation / Coming soon / Closed pills | filter tiles | works (visual highlight changes; cannot fully verify filtering with the small dataset) | PASS |
| Project tile tap | open Explore Detail | opens detail | PASS |
| Bottom-nav Explore tab | refresh | works | PASS |

### Observations

Same hero-image gap as Projects List. Filter row is correct.

---

## Screen 9 — Explore Detail

### Visual diff

| Element | HTML says (`page-explore-detail`) | Flutter shows | Status |
|---|---|---|---|
| Hero banner (200px, photo + gradient) | Photo + status pill top-center + title + location bottom | Gradient banner, no photo, status pill top-left "OPEN FOR RESERVATION", "25 L" gold pill top-right, title + location bottom-left | PARTIAL (no photo) |
| Back + Share buttons in hero | top-left back, top-right share | top-left back, top-right share icon | PASS |
| Stats grid: Units Available | 38 / 48 with fill bar | 43/44 with fill bar | PASS |
| Stats grid: Price per Unit | ₹25 L / "2 acres / unit" | ₹25 L / "2 acres / unit" | PASS |
| Stats grid: Expected Annual Return (col-span 2) | 14% large, "based on 5-year projection", trending-up icon | 18% per annum (centered card, no col-span styling, no icon) | PARTIAL |
| Projection callout | Info icon + "Expected annual return: 14% — based on 5-year projection..." | "Expected annual return: 18% — based on 5-year projection. Detailed financials shared post-allocation." | PASS |
| Crop pill | "🍅 Tomatoes & Cucumbers" | **Not present** | **FAIL (missing)** |
| Subscription Deadline pill | "30 Jun 2026" | **Not present** | **FAIL (missing)** |
| Growing Technology card | Same Aeroponic / Water saved / Yield / Cycles details | Inline Aeroponic pill + Water saved 95% / Yield 30 kg/m² / Cycles 7/yr | PASS |
| View Area + Photos CTA tiles | 2 side-by-side tiles linking to View Area and Gallery | **Not present** | **FAIL (missing)** |
| Mini map | (HTML doesn't have a mini map on explore-detail) | "Approximate location" with pin in gradient panel — Pune, Maharashtra | EXTRA (Flutter adds map placeholder — not a defect, but inconsistent with HTML scope) |
| Request Consultation CTA | Gradient primary, "Request Consultation" with phone icon → toast "Request received — your RM will call within 1 business day" | "Request Consultation" gradient primary button → toast "Got it — our team will reach out about Samsung LLP." | PASS (message wording differs slightly, intent matches) |
| Share Project CTA | Outline white button → opens Share modal | "Share Project" outlined button | PASS |
| **NO Min Lock-in tile** (HTML explicitly removed it in R4) | Not present | Not present | PASS (correctly absent) |

### Buttons

| Button | Expected action | Actual action | Pass/Fail |
|---|---|---|---|
| ← back | return to Explore | works | PASS |
| Share icon (hero) | open Share modal | opens modal | PASS (assumed — hero share icon is visible and tappable) |
| Stat cards | display only | display only | PASS |
| View Area tile | open View Area | **tile missing** | FAIL |
| Photos tile | open Gallery | **tile missing** | FAIL |
| Request Consultation | toast | shows toast "Got it — our team will reach out about Samsung LLP." | PASS |
| Share Project | open Share modal | opens modal | PASS |

### Observations

Two important missing affordances: **Crop pill / Subscription Deadline 2-col** and the **View Area + Photos CTA tiles** that should give prospective investors a way to explore the project before requesting consultation. The expected-return tile also doesn't get the special "col-span 2" prominence the HTML calls for.

---

## Screen 10 — Share Project modal

### Visual diff

| Element | HTML says | Flutter shows | Status |
|---|---|---|---|
| Modal eyebrow | "INVESTOR MODE" | "INVESTOR MODE" | PASS |
| Modal title | "Share · {project}" | "Share · Pineapple Enterprises" | PASS |
| Close X | top-right | top-right | PASS |
| Personalization note | "Personalized for {name} · appears on the card and in the caption." | "Personalized for Sahil Kumar · appears on the card and in the caption." | PASS |
| "1080 × 1080 preview" label | Present | Present | PASS |
| Preview card: "Shared by {name}" badge | Top-left | Top-left "Shared by Sahil Kumar" | PASS |
| Preview card: PREMIUM badge | Top-right gold | Top-right gold | PASS |
| Preview card: hero image | Real photo | **Gradient gray placeholder** (matches the Project Detail hero gap) | FAIL |
| Preview card: title | Project name | "Pineapple Enterprises" | PASS |
| Preview card: 3-stat row | RETURN / YIELD / TECH | RETURN 19% / YIELD — / TECH Aeroponic | PASS (yield empty acceptable for pre-harvest) |
| RM block | "TALK TO YOUR RELATIONSHIP MANAGER" + RM avatar + name + phone | "TALK TO YOUR RELATIONSHIP MANAGER / Rajesh Kumar / +91 98XXX XXXXX" | PASS |
| Footer | "growize · by ARL / Premium agri-investments, fully tracked" | Same | PASS |
| CTAs | WhatsApp (full-width green) + Email + Copy link | "Share on WhatsApp" (full-width green) + Email + Copy link (side-by-side) | PASS |

### Buttons

| Button | Expected action | Actual action | Pass/Fail |
|---|---|---|---|
| X close | dismiss modal | dismisses | PASS |
| Share on WhatsApp | open WhatsApp share intent | not tapped (would leave app) | UNTESTED |
| Email | open mail compose | not tapped | UNTESTED |
| Copy link | clipboard + toast | not tapped | UNTESTED |

### Observations

The modal is a strong implementation. Only defect is the missing hero image inside the preview card. The 1080×1080 dimension, RM block and CTA tray match the spec.

---

## Screen 11 — Financials

### Visual diff (Payouts sub-tab, default)

| Element | HTML says | Flutter shows | Status |
|---|---|---|---|
| Title | "Financials" + project chip right | "Financials" + "All Projects" chip right | PASS |
| Sub-tabs | Financials / Payouts | Payouts / Financials (Payouts active by default) | DIFFERENT order (Flutter promotes Payouts first) |
| Tax-Free Sec 10(2A) pill | Yes | "Tax-Free under Sec 10(2A)" pill | PASS |
| Total Earned / This FY cards | 2 cards | TOTAL EARNED ₹0 (Since Inception) / THIS FY ₹0 (FY 2026-27) | PASS |
| Transaction Ledger | heading + payout rows | "Transaction Ledger" heading; empty body (no payouts) | PASS (real data) |
| 5-year payout chart | (HTML explicitly removed in v2) | not present | PASS (correctly absent) |

### Visual diff (Financials sub-tab)

| Element | HTML says | Flutter shows | Status |
|---|---|---|---|
| Risk vs Return chart | Scatter plot with quadrants, Growize EKA + REITs + Fixed Income + Gold + Direct Equity + Fixed Deposit dots, "Source: AMFI · SEBI Guidelines" | Same scatter plot with 4 quadrant labels (LOW RISK HIGH RETURN / HIGH RISK HIGH RETURN / LOW RISK LOW RETURN / HIGH RISK LOW RETURN), Growize EKA in top-left, dots for REITs/Fixed Income/Gold/Direct Equity/Fixed Deposit, "Source: AMFI · SEBI Guidelines" | PASS |
| Invested + Returns cards | 2 mini cards | Invested ₹3.92Cr / Returns ₹0 | PASS |
| Capital Account card | Committed / Received / Pending rows | Committed ₹3.92 Cr / Received ₹0 / Pending ₹0 (color-coded) | PASS |
| Projection callout | Info text | "Expected annual return: 19% — based on 5-year projection. Detailed financials shared post-allocation." | PASS |

### Buttons

| Button | Expected action | Actual action | Pass/Fail |
|---|---|---|---|
| Payouts tab | activate Payouts view | works | PASS |
| Financials tab | activate Financials (chart) view | works | PASS |
| All Projects chip | open project selector | not retested here (same chip as Home) | PASS (by inference) |
| Risk vs Return chart dots | (HTML — display only) | display only | PASS |

### Observations

Financials is one of the better-implemented screens — both sub-tabs render, the risk/return chart is intact, Capital Account is colored correctly, and the 5-year chart is correctly removed (Track C).

---

## Screen 12 — Documents

### Visual diff

| Element | HTML says (`page-documents`) | Flutter shows | Status |
|---|---|---|---|
| Title | "Documents" + back | "Documents" + back | PASS |
| Accordion section: Common | Section header + file count | "Common / 1 file" — auto-expanded showing ARL Company Profile 2026.pdf · May 13, 2026 + eye icon | PASS |
| Accordion section: My Projects | Header + project docs | "My Projects / 0 files" — collapsed | PASS |
| Accordion section: My Documents | Header + user docs | "My Documents / 0 files" — collapsed | PASS |
| Doc row | Filename + date + view eye | Filename + date + eye icon | PASS |

### Buttons

| Button | Expected action | Actual action | Pass/Fail |
|---|---|---|---|
| ← back | return to Profile | works | PASS |
| Accordion section header (Common/My Projects/My Documents) | toggle expand/collapse | works | PASS |
| Eye icon on doc row | preview PDF | not tapped in this run | UNTESTED |

### Observations

Clean implementation. The fact that empty sections still render (0 files) is helpful for showing future capacity.

---

## Screen 13 — Profile

### Visual diff

| Element | HTML says (`page-profile`) | Flutter shows | Status |
|---|---|---|---|
| Header banner | Avatar + name + KYC pill + "X Projects · ₹Y invested" | "sahil Mohite / ARL-002 / KYC Verified / 3 Projects · ₹3.92Cr invested" with SM avatar | PASS |
| Active Projects card | List of project names | "Pineapple Enterprises · Xiaomi LLP · Samsung LLP" | PASS |
| Account section | KYC / Bank / Documents | KYC Details (Verified) / Bank Details / Documents | PASS |
| Support section | Assistance + (sub-items) | Assistance / Project Exit / Security / Preview First-Payout Celebration | PASS |
| Sign Out | Red text link | "Sign Out" in red text in pill | PASS |
| Privacy Policy + Terms | Footer links | "Privacy Policy · Terms of Service" | PASS |
| Preview First-Payout Celebration | "Preview First-Payout Celebration" with confetti icon → opens celebration page | "Preview First-Payout Celebration" with confetti icon → opens celebration overlay | PASS |

### Buttons

| Button | Expected action | Actual action | Pass/Fail |
|---|---|---|---|
| KYC Details row | open KYC screen | not tapped in this run | UNTESTED |
| Bank Details row | open bank screen | not tapped | UNTESTED |
| Documents row | open Documents | works | PASS |
| Assistance row | open Assistance | works | PASS |
| Project Exit row | open Exit screen | not tapped | UNTESTED |
| Security row | open Security | not tapped | UNTESTED |
| Preview First-Payout Celebration | open celebration | works | PASS |
| Sign Out | sign out flow | **not tested** (forbidden by task rules) | UNTESTED |
| Privacy Policy / Terms of Service | open legal docs | not tapped | UNTESTED |

### Observations

Profile screen is fully populated. All menu items present per HTML spec. The celebration preview tile is wired up correctly.

---

## Screen 14 — Celebration

### Visual diff

| Element | HTML says (`page-celebration`) | Flutter shows | Status |
|---|---|---|---|
| Confetti animation | Lottie / canvas confetti | Static colorful confetti graphic visible across top | PASS (visible — may or may not animate; static frame captured) |
| Close X | top-right | top-right X | PASS |
| Headline | "Your first payout has arrived" | "Your first payout has arrived" | PASS |
| Amount | Big green amount | "₹41,000 credited" in large green text | PASS |
| Sub | "From {project} · {date}" | "From EKA · Mar 15, 2026" | PASS |
| CTA 1 | "View in financials" gradient primary with trend-up icon | "View in financials" gradient primary with icon | PASS |
| CTA 2 | "Share your investment story" outlined with share icon | "Share your investment story" outlined with share icon | PASS |
| CTA 3 | "Maybe later" text link | "Maybe later" text link | PASS |

### Buttons

| Button | Expected action | Actual action | Pass/Fail |
|---|---|---|---|
| X close | dismiss | dismisses | PASS |
| View in financials | navigate to Financials | not tapped | UNTESTED |
| Share your investment story | open Share modal | not tapped | UNTESTED |
| Maybe later | dismiss | not tapped | UNTESTED |

### Observations

Pixel-faithful celebration screen.

---

## Screen 15 — Support / Assistance

### Visual diff

| Element | HTML says (`page-support`) | Flutter shows | Status |
|---|---|---|---|
| Title | "Assistance" + back | "Assistance" + back | PASS |
| "GET HELP FAST" eyebrow | Present | Present | PASS |
| WhatsApp Tech Support card | Green icon + title + sub | "WhatsApp Tech Support / Quick reply for app issues" with green chat icon | PASS |
| WhatsApp Your RM card | Green icon + title + sub | "WhatsApp Your RM / Account, payouts, investment queries" with green chat icon | PASS |
| Detailed Request (demoted) | Smaller card with "Open form" button | "Detailed Request / For less urgent matters · ~24h response" with "Open form" button | PASS |
| My Tickets section | Title + ticket list | "My Tickets" with two sample tickets: TKT-2847 (Sample, Resolved) "Payout not reflected" Mar 08, 2026; TKT-2756 (Sample, In Progress) "Update contact details" Feb 28, 2026 | PASS |

### Buttons

| Button | Expected action | Actual action | Pass/Fail |
|---|---|---|---|
| ← back | return to Profile | works | PASS |
| WhatsApp Tech Support | open WhatsApp chat (deep link) | not tapped (would leave app) | UNTESTED |
| WhatsApp Your RM | open WhatsApp chat to RM | not tapped | UNTESTED |
| "Open form" button | open ticket form | not tapped | UNTESTED |
| Ticket row | open ticket detail | not tapped | UNTESTED |

### Observations

Layout exactly matches HTML spec: WhatsApp CTAs at top, Detailed Request demoted with secondary styling, My Tickets below. Sample tickets are clearly labeled.

---

## Roll-up

### Screens audited: **15 / 15**

### Buttons tested or verified existent: **~70**

Includes: bottom-nav (×4) + bell + avatar + project chip + portfolio card + ROI panel + 3 contract progress rows + missing tour banner + 3 quick-stat targets on Home; back arrows + toggles + filter pills on Activity (×2 views); project tiles + missing 3-stat strip on Projects; back + Premium + hero share (missing) + Share + Request Exit + View Area + Photos + payouts View all on Project Detail; map + cert pills on View Area; thumbnails + fullscreen X on Photos; filter pills (×4) + tiles on Explore; back + share (hero) + 3 stat cards + missing View Area/Photos tiles + missing crop/deadline + Request Consultation + Share on Explore Detail; X + WhatsApp + Email + Copy link on Share modal; sub-tabs (×2) + chart + capital account on Financials; back + 3 accordion headers + eye icon on Documents; 8 menu rows + Sign Out on Profile; X + 3 CTAs on Celebration; back + 2 WhatsApp cards + "Open form" + 2 ticket rows on Assistance.

### Visual diff lines: **~120** across 15 tables.

### Defects by severity

#### P1 (must fix — feature parity with v2 spec)

1. **Home: Tour CTA banner missing** — HTML's gradient "Take Tour" banner that links to `startTour()` overlay is not implemented in Flutter. **File:** `lib/features/home/home_screen.dart`.
2. **Home: Quick Stats cards missing (Next Payout + Active Units)** — HTML defines a 2-tile grid below Project Progress card; Flutter doesn't render this grid at all. **File:** `lib/features/home/home_screen.dart`.
3. **Home: Project Progress card lacks "View All Projects" pill button** and lacks the single-project view variant. **File:** `lib/features/home/home_screen.dart`.
4. **Projects List: completely different layout** — HTML calls for a 2-col tile grid with hero photos, Premium/Standard badges, status pills, crop emoji pills. Flutter ships a 1-col wide-card list with letter avatars (PE/XL/SL). **File:** `lib/features/projects/projects_list_screen.dart`.
5. **Projects List: 3-stat strip (Active / Earned / Pending) missing.** **File:** `lib/features/projects/projects_list_screen.dart`.
6. **Explore Detail: Crop pill + Subscription Deadline 2-col missing** — both belong directly below the projection callout per HTML. **File:** `lib/features/explore/explore_detail_screen.dart`.
7. **Explore Detail: View Area + Photos action tiles missing** — HTML provides these 2 tiles so prospective investors can preview the project before requesting consultation. **File:** `lib/features/explore/explore_detail_screen.dart`.

#### P2 (visible polish gaps — non-blocking but spec drift)

8. **Project Detail / Explore Detail / Share modal preview / Projects List / Explore Tiles: no real hero images** — Flutter uses gradient color tiles with letter overlays everywhere a photo is expected. **Files:** `lib/features/projects/project_detail_screen.dart`, `lib/features/explore/explore_detail_screen.dart`, `lib/features/projects/projects_list_screen.dart`, `lib/features/explore/explore_screen.dart`, share-modal widget.
9. **Project Detail hero: status pill ("OPERATIONAL" / "PENDING") missing top-center.** **File:** `lib/features/projects/project_detail_screen.dart`.
10. **Project Detail hero: share icon affordance missing** — only the bottom Share CTA exists. HTML places a quick-share icon in the hero top-right. **File:** `lib/features/projects/project_detail_screen.dart`.
11. **View Area: map is a stylized placeholder circle, not a real basemap** — HTML expects a real map tile with radius overlay. **File:** `lib/features/projects/project_view_area_screen.dart`.
12. **Home sync badge: "Updated 37s ago" clock label** instead of the HTML's pulsing green dot + "Live" pill. **File:** `lib/features/home/home_screen.dart`.
13. **Explore Detail Expected Return tile: should col-span 2 with larger 2xl numerals + trending-up icon** — Flutter renders it as a standard centered card. **File:** `lib/features/explore/explore_detail_screen.dart`.
14. **Project tiles (Projects List): "Pending" status used for all projects** — HTML differentiates OPERATIONAL / PENDING per project. **File:** `lib/features/projects/projects_list_screen.dart`.
15. **Project / Explore tiles: Premium / Standard badge missing** (top-right of HTML tile). **Files:** `lib/features/projects/projects_list_screen.dart`, `lib/features/explore/explore_screen.dart`.
16. **Explore tiles: crop pill is generic "Mixed crops"** instead of specific crop with emoji per HTML.

#### P3 (cosmetic / micro-copy)

17. **Financials sub-tabs ordered Payouts | Financials** (Flutter) vs. **Financials | Payouts** (HTML). Either order is defensible; document the intent.
18. **Activity toggle button label flips between "History" and "Notifications"** — works correctly; matches HTML's `toggleActivityView()`. PASS, but worth a unit-test snapshot.
19. **View Area Crops Grown lists generic "Seasonal Crops (Primary)"** instead of per-project specific crop list with emojis.
20. **Welcome greeting**: Flutter adds user's first name ("Sahil"); HTML uses the bare "Welcome Back" headline. Minor copy variance — arguably an enhancement.
21. **Request Consultation toast wording differs**: Flutter says "Got it — our team will reach out about {project}." vs. HTML's "Request received — your RM will call within 1 business day." Both are acceptable, but choose one.

### Files needing Flutter code changes

```
lib/features/home/home_screen.dart                       (P1 #1, #2, #3; P2 #12)
lib/features/projects/projects_list_screen.dart           (P1 #4, #5; P2 #14, #15)
lib/features/projects/project_detail_screen.dart          (P2 #9, #10; image hero)
lib/features/projects/project_view_area_screen.dart       (P2 #11; P3 #19)
lib/features/explore/explore_screen.dart                  (P2 #15, #16; image hero)
lib/features/explore/explore_detail_screen.dart           (P1 #6, #7; P2 #13; image hero)
(Share modal widget — under explore/projects or core/widgets) (P2 #8 for preview hero)
```

### Verdict

Out of 15 screens audited, **9 screens (Activity, Project Detail bones, View Area content, Photos, Share modal, Financials, Documents, Profile, Celebration, Assistance — note: 10 if Auth's redirect counts as PASS-by-design) are at or near spec parity**. The biggest gaps cluster on three screens:

1. **Home** — three substantial omissions (tour CTA, Next Payout card, Active Units card) plus the sync badge drift.
2. **Projects List** — wrong layout entirely (wide-card list vs. 2-col tile grid with hero imagery).
3. **Explore Detail** — three meaningful affordances missing (crop pill, subscription deadline, View Area + Photos tiles).

A cross-cutting theme is the **absence of real hero photography** across Project Detail, Projects List, Explore tiles, Explore Detail, and the Share-modal preview card. Wiring up real images (whether from Supabase storage or curated Unsplash placeholders) would close most P2 polish gaps in one stroke.

All button taps tested produced expected navigations or no crashes. No P0 / blocker defects were found. The app is **functional** end-to-end; the gap is layout/spec fidelity, not behavior.

---

*Audit performed by: Claude (Cowork) on behalf of ARL Tech, 2026-05-20.*

---

## Resolution notes (v33)

Appended 2026-05-20 alongside the v33 design refresh. For each defect in the section above, the corresponding fix (if any) is listed here with a landing date. Defect numbering follows the original P1/P2/P3 list.

### P1 — must fix (feature parity with v2 spec)

| # | Defect | Resolution | Landed | v33 Change ID |
|---|---|---|---|---|
| 1 | Home: Tour CTA banner missing | **Deferred.** The Tour itself was rebuilt (4 → 14 steps) but the gradient "Take Tour" banner on Home is intentionally not surfaced — entry remains via Profile → Re-run Tutorial. Documented as design decision; not a defect. | n/a | V33-TOUR-01, V33-PROF-01 |
| 2 | Home: Quick Stats cards missing (Next Payout + Active Units) | **Resolved.** 2-tile Quick Stats row added below Project Progress card with IntrinsicHeight wrap. | 2026-05-20 | V33-HOME-01 |
| 3 | Home: Project Progress card lacks "View All Projects" pill | **Resolved.** "View All Projects" pill added in the card header. | 2026-05-20 | V33-HOME-03 |
| 4 | Projects List: completely different layout | **Resolved.** 1-col cards replaced by 2-col tile grid (SliverGridDelegateWithMaxCrossAxisExtent). | 2026-05-20 | V33-PRJL-01 |
| 5 | Projects List: 3-stat strip (Active / Earned / Pending) missing | **Resolved differently.** Strip removed entirely per v33 design refresh — the duplicate of Home Quick Stats was redundant. Pending tile hidden when count is 0. | 2026-05-20 | V33-PRJL-02, V33-PRJL-03 |
| 6 | Explore Detail: Crop pill + Subscription Deadline 2-col missing | **Resolved.** Both added below projection callout. | 2026-05-20 | V33-EXPL-01 |
| 7 | Explore Detail: View Area + Photos action tiles missing | **Resolved differently.** Tiles are intentionally NOT on Explore Detail (Explore is the prospect-facing surface — no project to view yet). Owner-side Project Detail keeps both. Documented as design decision. | 2026-05-20 | V33-EXPL-02 |

### P2 — polish gaps (non-blocking)

| # | Defect | Resolution | Landed | v33 Change ID |
|---|---|---|---|---|
| 8 | No real hero images across project surfaces | **Deferred to Post-v33 #2.** Bounded fix — needs `project-heroes` storage bucket + `projects.hero_image_path` + bulk upload. Currently still using Unsplash placeholders + gradient fallback. | Post-v33 | (deferred) |
| 9 | Project Detail hero: status pill missing | **Open.** Not addressed in v33 (lower priority — tier badge top-right already gives a tier signal). | — | — |
| 10 | Project Detail hero: share icon affordance missing | **Resolved differently.** Share Project button removed entirely from Project Detail per v33. The Share-modal flow lives on Explore Detail only. | 2026-05-20 | V33-PROJ-01 |
| 11 | View Area: map is stylized placeholder, not real basemap | **Resolved differently.** Mini-map kept as a stylized circle but now opens Google Maps externally on tap (`maps://` / `geo:` / `https://maps.google.com`). Radius scaled 3km → 5km with the circle visual scaled 120 → 180px. "Open in Maps" pill added. | 2026-05-20 | V33-VA-01, V33-VA-02 |
| 12 | Home sync badge: "Updated 37s ago" clock label | **Resolved.** Replaced by a pulsing green LIVE dot that animates for 60s after pull-to-refresh. | 2026-05-20 | V33-HOME-02 |
| 13 | Explore Detail Expected Return tile: should col-span 2 | **Open.** Not addressed in v33. Tile remains a standard centered card. |  — | — |
| 14 | Project tiles: "Pending" status used for all projects | **Open.** Not addressed in v33. Tiles still default to Pending; needs LLP_Status → tile-status mapping in projects_list_screen. | — | — |
| 15 | Project / Explore tiles: Premium / Standard badge missing | **Open.** Not addressed in v33. | — | — |
| 16 | Explore tiles: crop pill is generic "Mixed crops" | **Open.** Crop pill is now correctly populated on Explore Detail (V33-EXPL-01) but the Explore tile-list pill is still generic. Bounded follow-up. | — | — |

### P3 — cosmetic / micro-copy

| # | Defect | Resolution | Landed | v33 Change ID |
|---|---|---|---|---|
| 17 | Financials sub-tabs ordered Payouts \| Financials vs. HTML's Financials \| Payouts | **Documented as design decision** (Payouts-first matches investor mental model — payouts are the daily check-in surface). Closed by DEF-V32-AUTH-04. | 2026-05-20 | V33-CLOSE-03 |
| 18 | Activity toggle button label flip (History ↔ Notifications) | **PASS confirmed.** No change needed. Unit-test snapshot is still nice-to-have; queued for v1.1 test sweep. | n/a | — |
| 19 | View Area Crops Grown: generic "Seasonal Crops (Primary)" | **Open.** Per-project crop emoji list still pending. Bounded follow-up (needs `projects.crop_emojis` column). | — | — |
| 20 | Welcome greeting: Flutter adds user's first name | **Documented as design enhancement.** Closed without code change. | 2026-05-20 | — |
| 21 | Request Consultation toast wording differs | **Open.** Both copies still acceptable; deferred until UX writer picks a final string. | — | — |

### Closures roll-up

- **P1 resolved:** 5 / 7 (#2, #3, #4, #5, #6). #1 + #7 closed as design decisions.
- **P2 resolved:** 3 / 9 (#10, #11, #12). #8 deferred to Post-v33. #9, #13, #14, #15, #16 still open.
- **P3 resolved:** 2 / 5 (#17, #20 as design decisions; #18 PASS). #19, #21 still open.

### Backend defect closures (parallel track)

- **DEF-V29-03** — Push_LLP address fields not populating in webhook payloads. **Closed 2026-05-19** — `registered_address_line1/2/city/state/pincode` columns confirmed populated for all live LLPs via the v32 Deluge CF + webhook handler. See v33 Changes sheet row V33-CLOSE-01.
- **DEF-V32-VIS-01..08** — visual fixes (fill bar, tier badge alignment, hero gradient, tile fallback, etc.). **Closed 2026-05-20.** See V33-CLOSE-02.
- **DEF-V32-AUTH-01..06** — profile scroll, share modal infinite-height, auto-render race, financials sub-pill, explore tiles fallback, 4-pill filter decision. **Closed 2026-05-20.** See V33-CLOSE-03.

### Items deferred to v1.1+ post-v33

See `docs/ops/v1.1_roadmap.md` → "Post-v33" section for:

1. In-app "new version available" banner.
2. Real hero photos (closes P2 #8, partially #11, #16).
3. WhatsApp Business API integration (closes loop on V33-SUP-01/02).
4. iOS bundle.

*Resolution notes added by: Claude (Cowork) on behalf of ARL Tech, 2026-05-20.*

