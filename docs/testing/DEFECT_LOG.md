# Growize App — Defect Log

**Owner:** ARL Tech
**Created:** 2026-05-05
**Companion to:** `TEST_PLAN.md`, `SCENARIOS.md`, `ARL_Test_Tracker.xlsx`

This file is the index of all filed defects. Each defect has a one-row summary here and a full markdown file at `docs/testing/defects/DEF-####.md`.

---

## How to file a defect

1. Reproduce the issue **twice** before logging.
2. Pick the next sequential ID (e.g., `DEF-0001`).
3. Add a row to the **Index** table below.
4. Create `docs/testing/defects/DEF-####.md` from the template at the bottom of this document.
5. Add a row to the `Defects` sheet in `ARL_Test_Tracker.xlsx` mirroring the same fields.
6. Take screenshots; save under `docs/testing/defects/screenshots/DEF-####/` and reference them in the markdown.

---

## Index

| ID | Title | Linked TC | Layer | Severity | Priority | Status | Owner | Filed | Closed |
|----|-------|-----------|-------|----------|----------|--------|-------|-------|--------|
| _none yet_ | | | | | | | | | |

---

## Status legend

- **Open** — Filed, not yet triaged.
- **Triaged** — Severity/priority assigned; owner set.
- **In Progress** — Dev investigating / fixing.
- **Ready to Re-test** — Fix delivered to test build.
- **Closed-Pass** — Re-tested, defect resolved.
- **Closed-Won't Fix** — Triaged out (deferred / not a bug). Requires note.
- **Closed-Duplicate** — Reference the original defect ID.

---

## Layer legend

- **CRM** — Data does not exist or is wrong in Zoho CRM.
- **Sync** — Data is in CRM but did not propagate to Supabase.
- **Supabase** — Schema, query, or RLS issue at the database layer.
- **App** — Data is correct in Supabase but renders incorrectly in the Flutter app.
- **Auth** — Login, session, or investor mapping fault.
- **Mixed** — Spans more than one layer.

---

## Defect markdown template

> Copy the block below into `docs/testing/defects/DEF-####.md` and fill it in.

```markdown
# DEF-#### — <short title>

| Field | Value |
|---|---|
| **Filed by** | <name> |
| **Filed on** | YYYY-MM-DD |
| **Linked test case** | TC-XXX-###-## |
| **Linked scenario** | SC-XXX-### |
| **Environment** | Dev / Staging / Prod |
| **Build / commit** | <git sha or app version> |
| **Layer** | CRM / Sync / Supabase / App / Auth / Mixed |
| **Severity** | S1 / S2 / S3 / S4 |
| **Priority** | P0 / P1 / P2 / P3 |
| **Status** | Open |
| **Owner** | <unassigned> |

## Summary

<One-paragraph description of the bug.>

## Steps to reproduce

1.
2.
3.

## Expected result

<What should happen.>

## Actual result

<What actually happens.>

## Screenshots / evidence

- ![step 1](screenshots/DEF-####/01.png)
- Console / log excerpt:
  ```
  <paste relevant log lines>
  ```

## Test data used

- Investor: INV-XX
- Project: PRJ-XX
- Allocation: ALC-XX
- Other:

## Investigation notes (dev fills this)

### Hypothesis

### Findings

### Root cause

## Fix

- **Commit / PR:**
- **Files changed:**
- **Description of change:**

## Re-test

| Date | Tester | Result | Notes |
|---|---|---|---|

## Closure

- **Closed on:** YYYY-MM-DD
- **Closed by:**
- **Resolution:** Closed-Pass / Closed-Won't Fix / Closed-Duplicate
```

---

## Severity / Priority cheat-sheet

(Copied here for convenience — authoritative version in `TEST_PLAN.md`.)

| Severity | Use when… |
|---|---|
| **S1 — Critical** | Wrong investor sees wrong data. App crashes on launch. Auth bypass. Money figures wrong. |
| **S2 — High** | Allocation flow broken end-to-end. Project list empty when it shouldn't be. Sync fails silently. |
| **S3 — Medium** | One state of allocation renders incorrectly. Cosmetic gap with workaround. |
| **S4 — Low** | Copy issue, minor UI parity (spacing, color). |

| Priority | Use when… |
|---|---|
| **P0** | Launch-blocker; fix before 2026-05-05. |
| **P1** | Fix in this test cycle. |
| **P2** | Next sprint. |
| **P3** | Backlog. |

---

## Common patterns to watch

These keep recurring in audits — file as defects if observed:

- Demo persona data leaking into real account (project memory: `audit_phase1_findings`).
- RLS view exposing other investors' rows.
- Migration drift between dev/staging/prod schemas.
- Edge-function-only writes bypassed by direct INSERT policy.
- App reading stale Hive cache after CRM update.
