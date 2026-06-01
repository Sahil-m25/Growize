# Post-launch monitoring & alerts plan

This is the alerting posture for Growize after public launch. Tuned for a small team — alerts should be rare enough that every page is read, with manual escalation paths for the one or two cases that warrant a phone call.

## Scope and assumptions

- Two primary failure surfaces: the mobile app (crashes, render errors) and the Supabase backend (auth, webhooks, scheduled jobs).
- Single on-call rotation for v1 — `tech@agresearchlabs.com` is the primary inbox; WhatsApp is the human escalation channel for P1s.
- Alert fatigue is the failure mode we're most worried about. Thresholds below are deliberately conservative — better one missed soft-fail in the first week than a team that mutes Slack.

## Pre-flight blockers

**DEF-V31-05** — the `zoho-reconcile-daily` cron job is currently throwing 500s on production. Wiring up "scheduled job failure" alerting before this is cleaned up will spam the inbox every 24 hours and train the team to ignore it. Either fix the cron or temporarily suppress that specific job's alert with a comment in the alert rule pointing at this defect ID. Do not enable monitoring globally until that's resolved.

## Sentry alerts

The DSN is wired in `lib/main.dart` and crash-reporting is the only signal we collect for v1 (no performance tracing). Configure these rules in the Sentry EU project for Growize:

| Rule | Threshold | Action |
| --- | --- | --- |
| High error rate | More than 5 events/min sustained over a 10-min window | Email `tech@agresearchlabs.com` |
| Crash-free sessions falling | Crash-free rate < 99% over rolling 1h, 1k+ sessions sampled | Email `tech@agresearchlabs.com`, WhatsApp on-call |
| New issue first seen | Any issue tagged `level:error` or higher, first seen, environment=production | Email `tech@agresearchlabs.com` |
| Regression | Resolved issue re-occurs in production | Email `tech@agresearchlabs.com` |

Set the project's "issue grouping" to default and enable the auto-resolve-after-30-days rule so stale noise drops off.

## Supabase alerts

Supabase doesn't have first-class alerting parity with Sentry — the practical pattern is to run a tiny scheduled function that runs the queries below and emails on threshold breach, or to wire the same queries to a Grafana / Metabase dashboard with alerts. Either works. Don't over-engineer.

| Rule | Threshold | Action |
| --- | --- | --- |
| Webhook failure rate | > 10% of webhook_log rows in last 1h have `status='failed'`, minimum 20 rows | Email `tech@agresearchlabs.com` |
| Scheduled job failure | Any cron edge function returning non-2xx in last 24h (excluding `zoho-reconcile-daily` until DEF-V31-05 is closed) | Email `tech@agresearchlabs.com` |
| Auth signup failure rate | > 20% of `auth.users` insert attempts failing over rolling 1h (use Supabase logs) | Email `tech@agresearchlabs.com` |
| Daily reconcile job failure | `zoho-reconcile-daily` not having a successful run in 36h (once DEF-V31-05 lands) | Email `tech@agresearchlabs.com`, WhatsApp on-call |

## Dashboard queries

Run these as scheduled queries (Metabase/Grafana/whatever) or paste into Supabase SQL editor for spot-checks.

**Webhook failure rate, last hour:**

```sql
SELECT
  count(*) FILTER (WHERE status = 'failed')::float
    / NULLIF(count(*), 0) AS failure_rate,
  count(*) FILTER (WHERE status = 'failed') AS failed_count,
  count(*) AS total_count
FROM webhook_log
WHERE received_at > NOW() - INTERVAL '1 hour';
```

**Most recent webhook failures with error message:**

```sql
SELECT received_at, source, status, error_message
FROM webhook_log
WHERE status = 'failed'
  AND received_at > NOW() - INTERVAL '24 hours'
ORDER BY received_at DESC
LIMIT 50;
```

**Recent signup failures (relies on `auth_audit_log` if present, else Supabase Auth logs):**

```sql
SELECT count(*) AS failed_signups
FROM auth.audit_log_entries
WHERE created_at > NOW() - INTERVAL '1 hour'
  AND payload->>'action' = 'user_signedup_failed';
```

**Scheduled function failure check (requires `cron.job_run_details` from pg_cron):**

```sql
SELECT jobid, runid, job_pid, database, username, command,
       status, return_message, start_time, end_time
FROM cron.job_run_details
WHERE start_time > NOW() - INTERVAL '36 hours'
  AND status != 'succeeded'
ORDER BY start_time DESC;
```

## Review cadence

- **First month post-launch:** weekly review every Monday morning. Walk the Sentry issues list, the webhook failure dashboard, and cron history. Triage anything new, close stale issues, adjust thresholds if a real signal is being missed or a false positive is recurring.
- **After month one:** biweekly review. Drop back to monthly only once two consecutive biweekly reviews surface nothing actionable.
- Keep a one-line "what changed this week" note in this doc each review — it makes the next person's life easier.

## Channels

| Severity | Channel | Trigger |
| --- | --- | --- |
| P3 (informational) | Email to `tech@agresearchlabs.com` | New non-recurring Sentry issue, single failed webhook |
| P2 (investigate within 24h) | Email + a heads-up note in the team Slack `#growize-ops` channel if one exists | Sustained elevated error rate, scheduled job degraded |
| P1 (page now) | Email + WhatsApp the on-call human directly | Crash-free rate breach, auth fully broken, reconcile job dead 36h+ |

WhatsApp escalation is intentionally manual for v1 — no PagerDuty wiring yet. The on-call human reads the email, decides P1, and calls. Revisit if alert volume crosses ~10/week.

## What we're explicitly not alerting on (yet)

- Performance / latency (no tracing in v1).
- Cost spikes (Supabase + Sentry usage stay well under quotas at current scale).
- Failed login attempts at the user level (privacy-sensitive, low signal).
- Crash-free *users* (sessions metric is sufficient at our volume).

Revisit this list at the first biweekly review.
