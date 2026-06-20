# Growize — Manual Smoke-Test Checklist

Fast, prioritised UI/E2E pass to run after each deploy. The backend/RLS/security
cases are already automated (11/11 passing); this covers what needs human eyes.

**Test on:** https://growizefarm.com (after the latest build is deployed)
**You need:** (1) a real investor login with allocations, (2) a *second* investor
account to prove data isolation, (3) ideally one Zoho LLP/Contact with a test PDF
attached to validate document sync end-to-end.
**Mark each:** ☐ = not run · ✅ pass · ❌ fail (note the issue) · ⛔ blocked · n/a

---

## P0 — Launch-critical (all must pass)

### Auth & session
- [ ] Sign in with a registered email → OTP/magic-link → lands on Home with **real** data (not demo).
- [ ] Wrong/expired OTP → clear error, no session.
- [ ] Logged-out browsing shows **demo data with “Sample” badges**; no real investor data leaks.
- [ ] Sign out → returns to auth; re-opening does not show the previous user’s data.

### Home / portfolio
- [ ] Portfolio totals (value, invested, returns, active units) look correct and INR-formatted.
- [ ] **Contract Progress**: the %, the bar fill, and “Month X of Y” all agree (single project and All-Projects views).
- [ ] **“Outperforming” badge is HIDDEN when ROI ≤ 12%** and only appears above 12% *(new — needs the latest deploy)*.
- [ ] Project selector rescopes the portfolio + progress; greeting/name stays put; long names don’t overflow.
- [ ] Cold load shows a skeleton then resolves (never an endless spinner).

### Consent & onboarding *(new)*
- [ ] New-investor onboarding shows **two separate ticks**: required (Terms + Privacy) and optional (marketing).
- [ ] Submit is **blocked until the required tick** is checked; optional can be left unchecked.
- [ ] Terms / Privacy links open the documents; Privacy Notice reads **v1.1**.

### Privacy & rights *(new)*
- [ ] Profile → Security → **Privacy & Consent**: marketing toggle flips on/off and persists after refresh.
- [ ] **Manage my data & rights** opens the Privacy Center.
- [ ] **Download my data** produces a JSON copy of the user’s data.
- [ ] **Nominee**: add → edit → remove all work and persist.
- [ ] **Request data erasure** shows the confirm dialog (with the statutory-retention notice) and records the request.

### Documents *(fixed)*
- [ ] Documents tab shows **clean empty sections** — no dummy rows that fail to open.
- [ ] If a real file exists: tapping opens it in the in-app viewer; if not, it shows **“Not available yet”** (no broken tab/URL).

### Routing & resilience *(new)*
- [ ] **Refresh the page** on /projects, /financials, /privacy-center → the screen reloads (no “Page not found” / 404).
- [ ] A shared deep link (e.g. a project link) opens directly.
- [ ] Force a network failure → screens show a friendly “couldn’t load / Retry”, not a blank or endless spinner.
- [ ] No raw red error screen anywhere (global error boundary catches it).

### Data isolation (compliance — use the 2nd account)
- [ ] Second investor **cannot** see the first investor’s documents, units, or payouts.
- [ ] Project documents only appear for investors who hold units in that project.

---

## P1 — Important

### Projects
- [ ] Projects grid renders (hero, status pill, tier, units, invested, progress, next payout).
- [ ] Project detail loads: phase timeline, monthly updates, allocation, documents row.
- [ ] Invalid/removed project id → “Project not found” (no crash); offline → Retry card.

### Financials
- [ ] Summary cards + payouts ledger render; empty ledger shows the empty state (until payouts are populated).
- [ ] FY-earned figure is sensible; amounts INR-formatted.

### Activity & gallery
- [ ] Notifications list + unread badge; “mark all read” works and persists.
- [ ] Gallery renders grouped photos (or a clean empty state until populated).

### Profile / settings
- [ ] Profile header shows correct name/email.
- [ ] KYC screen status + resubmission; Bank details change → goes through the request flow (no direct write); both have error states.
- [ ] Security: app-lock / biometric toggles (mobile) and notifications toggle persist.

### Support / exit
- [ ] Create ticket → appears in list; reply updates the thread.
- [ ] Exit eligibility screen renders; pending exit shows clearly.

---

## P2 — Nice-to-have

- [ ] Explore shows “Coming Soon” (feature gated).
- [ ] Large font / accessibility: layouts adapt without clipping.
- [ ] Web responsive: usable at desktop and narrow widths; mouse/trackpad scroll works.
- [ ] No console errors during a full walkthrough (DevTools → Console).

---

## Known empty-until-populated (not bugs — data tasks)
Payouts, project phases, monthly updates, gallery, document files, and crops are
currently empty. Expect those surfaces to show empty/“not available” states until
the data is seeded and the Zoho sync delivers files. Re-run the document and gallery
rows above **after** a real Zoho attachment + sync.
