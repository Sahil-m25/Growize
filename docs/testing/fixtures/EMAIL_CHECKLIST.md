# Test Investor Email Checklist

**Why this exists:** Every demo investor needs a real, OTP-receivable inbox. Without it, app login flows can't complete, and the auth/RLS scenarios become untestable. This file lists the addresses, what each is used for, and the provisioning steps you (ARL Tech) need to complete before fixture creation runs.

**Domain placeholder:** `arl.test` is NOT a deliverable domain. **Replace with a domain you control** — a subdomain of `agresearchlabs.com` (e.g., `demo.agresearchlabs.com`) is the recommended option. Once decided, find/replace `@arl.test` across the fixture spec.

---

## Required mailboxes

| Fixture | Email (placeholder) | Purpose | Notes |
|---|---|---|---|
| F-INV-01 | demo-aarav@arl.test | Paid + Active scenario; **also Daily UAT service account** | Most important — the daily agent logs in here. Long-lived auth token to be issued post-onboarding. |
| F-INV-02 | demo-ishita@arl.test | Paid + Not Started scenario | OTP needed for login tests. |
| F-INV-03 | demo-rohan@arl.test | Pending payment scenario | OTP needed. |
| F-INV-04 | demo-priya@arl.test | Partial payment scenario | OTP needed. |
| F-INV-05 | demo-vikram@arl.test | Multi-LLP scenario | OTP needed. |
| F-INV-06 | demo-empty@arl.test | Zero-allocation empty-state | OTP needed. |
| F-INV-07 | demo-duplicate@arl.test | Duplicate-email negative test (two contacts share this) | Single inbox; both Zoho contacts resolve here. |

Total: **7 mailboxes** (F-INV-07-twin shares with F-INV-07).

---

## Provisioning steps — your action items

### Option A — Catch-all on a controlled subdomain (recommended)

1. Choose a subdomain you own (suggest: `demo.agresearchlabs.com`).
2. In your DNS, create a single MX record pointing to a mailbox you can read (Zoho Mail, Google Workspace, etc.).
3. Configure that mailbox as a catch-all so anything sent to `demo-*@demo.agresearchlabs.com` lands in one inbox.
4. Confirm receipt by sending a test email to `demo-test@demo.agresearchlabs.com`.
5. Update fixture spec: find/replace `@arl.test` → `@demo.agresearchlabs.com` in `fixture_payloads.json`.
6. Tick the box below.

- [ ] Catch-all configured and verified.
- [ ] `fixture_payloads.json` updated with the real domain.

### Option B — Individual aliases (only if catch-all not feasible)

1. Provision 7 distinct alias addresses on your existing domain, all forwarding to one inbox.
2. Verify each alias receives mail.
3. Update fixture spec to match.

- [ ] All 7 aliases provisioned.
- [ ] Each alias verified (sent and received a test email).
- [ ] `fixture_payloads.json` updated.

---

## Daily UAT service account — extra setup

The Daily UAT scheduled task needs to log in as F-INV-01 every morning **without human OTP entry**. Options, in order of preference:

1. **Long-lived JWT issued by Supabase service role on behalf of F-INV-01.** Stored in scheduler secret manager. Rotated quarterly.
2. **Bypass-OTP env flag for `demo-*@…` domain.** Risky in prod; only enable in staging.
3. **Email-relay parser** that programmatically reads the OTP from the inbox and submits it. Most fragile; defer.

- [ ] Decide on auth method for the Daily UAT agent.
- [ ] Issue and store the credential securely.
- [ ] Document the rotation date in `DAILY_UAT_RUNBOOK.md` (already references quarterly rotation).

---

## What I (the assistant) cannot verify

- Whether your DNS has an MX record.
- Whether the inbox actually receives mail.
- Whether Zoho Mail / your provider is configured.
- Whether the OTP route delivers to the chosen domain.

These are all human steps. Once you tick the boxes above and confirm, the fixture creation can proceed safely.

---

## Acceptance check (before fixture creation runs)

Tester confirms in this file:

- [ ] All 7 mailboxes exist and receive mail (one test send each).
- [ ] Domain in `fixture_payloads.json` matches the working domain.
- [ ] Daily UAT credential decided + stored.

When all three are ticked, the canary fixture create (F-LLP-A) is safe to execute.
