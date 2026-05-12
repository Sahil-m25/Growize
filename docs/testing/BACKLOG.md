# Testing — Backlog

**Owner:** ARL Tech
**Created:** 2026-05-05

Items deliberately deferred from the current launch cycle. Re-evaluate after launch.

---

## Analytics

### B-01 — PostHog analytics integration

**Status:** Deferred
**Why:** Out of scope for pre-launch testing cycle.
**What:** Wire PostHog events for screen views, key actions (login, project view, document open), and crash funnels. Use it to drive a post-launch quality dashboard alongside Sentry.
**When to revisit:** Within first 4 weeks after launch.
**Notes:** Confirm PII boundaries — investor identifiers must be hashed/aliased; do not send raw email or phone.

---

## Test scope deferrals

### B-02 — iOS-specific testing

**Why:** Android + web prioritized for launch; iOS build path validated separately.
**Revisit:** Once iOS build is signed and in TestFlight.

### B-03 — Performance / load testing

**Why:** Read-heavy app, low concurrent user count at launch.
**Revisit:** Before scaling beyond ~500 concurrent investors.

### B-04 — Localization (i18n)

**Why:** Single-language launch.
**Revisit:** When second language is committed.

### B-05 — Push notification end-to-end testing

**Why:** Notifications module not in launch scope.
**Revisit:** When notifications feature is implemented.

---

## Test infrastructure

### B-06 — Replace manual weekly UAT with semi-automated visual regression

**Why:** Currently weekly human pass; long-term we want screenshot diffs against the HTML prototype.
**Revisit:** After launch stability confirmed.
**Tools to evaluate:** Playwright + visual regression, Flutter integration tests with golden files.

### B-07 — Synthetic monitoring beyond daily UAT

**Why:** Daily UAT runs once per day; production incidents can happen any time.
**Revisit:** Post-launch.
**Idea:** A lighter sub-set of D-01..D-18 every 15 minutes via Supabase scheduled job.

### B-08 — Chaos / failure injection tests

**Why:** Useful but premature.
**Revisit:** After 3 months of stable operation.
**Idea:** Periodically force edge function failure, sync delay, RLS misconfig in staging and confirm system degrades gracefully.

---

## Process

### B-09 — Defect SLA tracker

**Why:** Currently severity/priority captured but no time-to-close metric.
**Revisit:** Once defect volume justifies it (>20 defects/month).

### B-10 — Test data refresh automation

**Why:** Currently manual: admin creates `-demo` records in CRM and types CRM IDs into the fixture spec.
**Revisit:** If fixture set grows beyond ~30 records.
**Idea:** A small admin script that lists all `-demo` records by name pattern and renders the fixture spec table.

---

## Captured but not yet evaluated

(Add new items here as they come up; triage later.)

| Date added | Item | Source / Notes |
|---|---|---|
| 2026-05-05 | PostHog analytics | User direction |
