#!/usr/bin/env python3
"""
sync_fixtures.py — Push the 19 -demo CRM fixtures into Supabase.

WHY THIS EXISTS
---------------
The Zoho workflow rule that should trigger zoho-crm-webhook didn't fire when
the fixtures were created via API. This script is the manual catch-up:
  1. onboard-investor   — creates investors rows + sends password-setup emails
                          for the 7 demo Contacts (so allocations have a row
                          to attach to).
  2. crm-resync         — pushes 5 LLP records and 7 Allocation records
                          through the same upsert logic the webhook uses.

WHAT YOU NEED
-------------
A `.env.local` next to this script with:

    SUPABASE_URL=https://oynfhdqizebvgmaoiuax.supabase.co
    ADMIN_SECRET=<onboard-investor secret>
    ADMIN_RESYNC_SECRET=<crm-resync secret>
    ZOHO_TOKEN=<zoho oauth bearer for record reads>

ZOHO_TOKEN is needed because crm-resync expects the FULL Zoho record JSON in
the body. We re-fetch each record by id before pushing. If you don't have a
token handy, the script can fall back to the minimal record we already
created (see --inline-records flag) — but the webhook handler will get
fewer fields, which is fine for our test data.

USAGE
-----
    cd docs/testing/fixtures
    python3 sync_fixtures.py            # full run, fetches Zoho records
    python3 sync_fixtures.py --inline-records   # use known fixture data, skip Zoho fetch
    python3 sync_fixtures.py --dry-run  # print what would be sent, do nothing
    python3 sync_fixtures.py --only investors    # phase 1 only
    python3 sync_fixtures.py --only llps         # phase 2 only
    python3 sync_fixtures.py --only allocations  # phase 3 only

OUTPUT
------
A timestamped log at sync_run_YYYYMMDD_HHMMSS.log with every request, response,
and verification SQL. Tails the log to stdout while running.
"""

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime
from pathlib import Path

# ─────────────────────────────────────────────────────────────────────────────
# Hard-coded fixture identifiers — match docs/testing/fixtures/fixture_payloads.json.
# Update these if the fixture spec changes.
# ─────────────────────────────────────────────────────────────────────────────

CONTACTS = [
    # (zoho_contact_id, fixture_key, last_name, first_name, email, mobile, pan)
    ("1169101000001467016", "F-INV-01", "Aarav-demo",     "Sharma-demo",   "sahilmhl25+demo-aarav@gmail.com",     "+91-90000-00001", "DEMO01A1ZX"),
    ("1169101000001467017", "F-INV-02", "Ishita-demo",    "Patel-demo",    "sahilmhl25+demo-ishita@gmail.com",    "+91-90000-00002", "DEMO02A1ZX"),
    ("1169101000001467018", "F-INV-03", "Rohan-demo",     "Mehta-demo",    "sahilmhl25+demo-rohan@gmail.com",     "+91-90000-00003", "DEMO03A1ZX"),
    ("1169101000001467019", "F-INV-04", "Priya-demo",     "Iyer-demo",     "sahilmhl25+demo-priya@gmail.com",     "+91-90000-00004", "DEMO04A1ZX"),
    ("1169101000001467020", "F-INV-05", "Vikram-demo",    "Joshi-demo",    "sahilmhl25+demo-vikram@gmail.com",    "+91-90000-00005", "DEMO05A1ZX"),
    ("1169101000001467021", "F-INV-06", "Empty-demo",     "Investor-demo", "sahilmhl25+demo-empty@gmail.com",     "+91-90000-00006", "DEMO06A1ZX"),
    ("1169101000001467022", "F-INV-07", "Duplicate-demo", "Email-A-demo",  "sahilmhl25+demo-duplicate@gmail.com", "+91-90000-00007", "DEMO07A1ZX"),
]

LLPS = [
    # (zoho_id, fixture_key, name, total_units, pet_unit_price, llp_status, tier, yield)
    ("1169101000001433001", "F-LLP-A",    "Alpha Mango LLP-demo",   1000, 10000, "Active",                   "1 CR",  "20%"),
    ("1169101000001433016", "F-LLP-A2",   "Alpha Avocado LLP-demo",  500, 20000, "Open for Reservation",     "1 CR",  "23%"),
    ("1169101000001433017", "F-LLP-B",    "Beta Banana LLP-demo",    800,  5000, "Active",                   "50 L",  "25%"),
    ("1169101000001439003", "F-LLP-C",    "Gamma Empty LLP-demo",      0,     0, "Darft",                    "10 L",  None),
    ("1169101000001433018", "F-LLP-EXIT", "Delta Exited LLP-demo",   600, 15000, "Fully Subscribed / Closed","1 CR",  "27%"),
]

ALLOCATIONS = [
    # (zoho_alloc_id, fixture_key, name, customer_id, llp_id, reserved_units, issued_units,
    #  unit_price, total_llp_units, capital_invested, capital_returns, alloc_status, customer_status,
    #  yield, amount_1, date_1, utr, investment_date)
    ("1169101000001466002","F-ALC-01",  "Aarav-AlphaMango-001-demo",     "1169101000001467016","1169101000001433001",  50,  50, 10000, 1000,500000,     0,"Issued","Active","20%",500000,"2026-04-01","DEMOUTR000001","2026-04-01"),
    ("1169101000001430008","F-ALC-02",  "Ishita-AlphaAvocado-001-demo",  "1169101000001467017","1169101000001433016",  25,   0, 20000,  500,500000,     0,"Reserved","Active","23%",500000,"2026-04-15","DEMOUTR000002","2026-04-15"),
    ("1169101000001430009","F-ALC-03",  "Rohan-AlphaMango-001-demo",     "1169101000001467018","1169101000001433001",  30,   0, 10000, 1000,     0,     0,"Reserved","Active","20%",  None,        None,         None,        "2026-04-20"),
    ("1169101000001430010","F-ALC-04",  "Priya-AlphaMango-001-demo",     "1169101000001467019","1169101000001433001",  40,  20, 10000, 1000,200000,     0,"Reserved","Active","20%",200000,"2026-04-22","DEMOUTR000004","2026-04-22"),
    ("1169101000001430011","F-ALC-05",  "Vikram-AlphaMango-001-demo",    "1169101000001467020","1169101000001433001",  20,  20, 10000, 1000,200000,     0,"Issued","Active","20%",200000,"2026-04-10","DEMOUTR000005","2026-04-10"),
    ("1169101000001430012","F-ALC-06",  "Vikram-BetaBanana-001-demo",    "1169101000001467020","1169101000001433017", 100, 100,  5000,  800,500000,     0,"Issued","Active","25%",500000,"2026-04-12","DEMOUTR000006","2026-04-12"),
    ("1169101000001430013","F-ALC-EXIT","Aarav-DeltaExited-001-demo",    "1169101000001467016","1169101000001433018",  20,  20, 15000,  600,300000, 60000,"Issued","Exited Fully","27%",300000,"2025-10-01","DEMOUTREXIT01","2025-10-01"),
]

# ─────────────────────────────────────────────────────────────────────────────
# Plumbing
# ─────────────────────────────────────────────────────────────────────────────

LOG_PATH: Path | None = None


def log(msg: str) -> None:
    """Append to log file and print to stdout."""
    line = f"[{datetime.now().isoformat(timespec='seconds')}] {msg}"
    print(line)
    if LOG_PATH:
        with LOG_PATH.open("a", encoding="utf-8") as f:
            f.write(line + "\n")


def load_env(path: Path) -> dict[str, str]:
    """Lightweight .env parser. Lines like KEY=value, comments with #."""
    if not path.exists():
        log(f"WARN: {path} not found — falling back to environment variables")
        return dict(os.environ)
    out: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        s = raw.strip()
        if not s or s.startswith("#"):
            continue
        if "=" not in s:
            continue
        k, v = s.split("=", 1)
        out[k.strip()] = v.strip().strip('"').strip("'")
    # also merge environ (env vars override .env.local? no — .env.local wins for explicit fixture work)
    for k, v in os.environ.items():
        out.setdefault(k, v)
    return out


def http_post(url: str, headers: dict[str, str], body: dict, dry: bool, timeout: int = 30) -> tuple[int, dict]:
    if dry:
        log(f"DRY RUN POST {url}")
        log(f"          headers: { {k: ('***' if 'secret' in k.lower() else v) for k, v in headers.items()} }")
        log(f"          body keys: {list(body.keys())}")
        return (200, {"dry_run": True})
    data = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, json.loads(resp.read().decode("utf-8") or "{}")
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8") if e.fp else ""
        try:
            parsed = json.loads(body) if body else {}
        except Exception:
            parsed = {"raw": body}
        return e.code, parsed
    except Exception as e:
        return 0, {"error": str(e)}


# ─────────────────────────────────────────────────────────────────────────────
# Phase 1 — onboard investors
# ─────────────────────────────────────────────────────────────────────────────

def phase_investors(env: dict, dry: bool) -> list[tuple[str, int, dict]]:
    url = f"{env['SUPABASE_URL']}/functions/v1/onboard-investor"
    secret = env.get("ADMIN_SECRET")
    if not secret:
        log("ERROR: ADMIN_SECRET missing — cannot run phase_investors")
        return []
    log(f"\n── PHASE 1: onboard-investor — {len(CONTACTS)} contacts ──")
    out = []
    for (zoho_id, fkey, last, first, email, phone, _pan) in CONTACTS:
        body = {
            "email":            email,
            "name":             f"{first} {last}".strip(),
            "arl_id":           f"ARL-{fkey}",
            "zoho_contact_id":  zoho_id,
            "phone":            phone,
            "salutation":       "Mr.",
        }
        headers = {
            "Content-Type":           "application/json",
            "X-ARL-Admin-Secret":     secret,
        }
        log(f"  → {fkey} {email}")
        status, resp = http_post(url, headers, body, dry)
        log(f"    status={status} resp={json.dumps(resp)[:200]}")
        out.append((fkey, status, resp))
        time.sleep(0.5)
    return out


# ─────────────────────────────────────────────────────────────────────────────
# Phase 2 — crm-resync LLPs
# ─────────────────────────────────────────────────────────────────────────────

def phase_llps(env: dict, dry: bool) -> list[tuple[str, int, dict]]:
    url = f"{env['SUPABASE_URL']}/functions/v1/crm-resync"
    secret = env.get("ADMIN_RESYNC_SECRET")
    if not secret:
        log("ERROR: ADMIN_RESYNC_SECRET missing — cannot run phase_llps")
        return []
    log(f"\n── PHASE 2: crm-resync (LLPs) — {len(LLPS)} records ──")
    out = []
    for (zoho_id, fkey, name, total_units, ppu, status, tier, yld) in LLPS:
        data: dict = {
            "id":                 zoho_id,
            "Name":                name,
            "Total_Units":         total_units,
            "Pet_Unit_Price":      ppu,
            "LLP_Status":          status,
            "Tier":                tier,
            "LLP_Owner":           "ARL Demo Owner",
            "No_of_partners":      2,
        }
        if yld:
            data["Annual_Rental_Yield"] = yld
        body = {"module": "LLP_Creation_Module", "data": data}
        headers = {
            "Content-Type":          "application/json",
            "X-ARL-Admin-Secret":    secret,
        }
        log(f"  → {fkey} {name}")
        st, resp = http_post(url, headers, body, dry)
        log(f"    status={st} resp={json.dumps(resp)[:200]}")
        out.append((fkey, st, resp))
        time.sleep(0.5)
    return out


# ─────────────────────────────────────────────────────────────────────────────
# Phase 3 — crm-resync Allocations
# ─────────────────────────────────────────────────────────────────────────────

def phase_allocations(env: dict, dry: bool) -> list[tuple[str, int, dict]]:
    url = f"{env['SUPABASE_URL']}/functions/v1/crm-resync"
    secret = env.get("ADMIN_RESYNC_SECRET")
    if not secret:
        log("ERROR: ADMIN_RESYNC_SECRET missing — cannot run phase_allocations")
        return []
    log(f"\n── PHASE 3: crm-resync (Allocations) — {len(ALLOCATIONS)} records ──")
    out = []
    for (zoho_id, fkey, name, customer_id, llp_id, reserved, issued, unit_price,
         total_llp_units, capital_invested, capital_returns, alloc_status,
         customer_status, yld, amt1, date1, utr, investment_date) in ALLOCATIONS:
        data: dict = {
            "id":                       zoho_id,
            "Customer":                 {"id": customer_id},
            "LLP":                      {"id": llp_id},
            "Reserved_Units":           reserved,
            "Issued_Units":             issued,
            "Unit_Price":               unit_price,
            "Total_LLP_Units":          total_llp_units,
            "Capital_Invested":         capital_invested,
            "Capital_Returns":          capital_returns,
            "Allocation_Status":        alloc_status,
            "Customer_Status":          customer_status,
            "Annual_Rental_Yield":      yld,
            "Investment_Date":          investment_date,
        }
        if amt1 is not None:
            data["Amount_1"] = amt1
            data["Date_1"]   = date1
            data["UTR_1"]    = utr   # NOTE: webhook handler reads UTR_N (not UTR), per index.ts loop i=1..10
        body = {"module": "LLP_UnitAllocation_Module", "data": data}
        headers = {
            "Content-Type":          "application/json",
            "X-ARL-Admin-Secret":    secret,
        }
        log(f"  → {fkey} {name}")
        st, resp = http_post(url, headers, body, dry)
        log(f"    status={st} resp={json.dumps(resp)[:200]}")
        out.append((fkey, st, resp))
        time.sleep(0.5)
    return out


# ─────────────────────────────────────────────────────────────────────────────
# Verification — SQL queries (printed; user runs them manually OR pipe to psql)
# ─────────────────────────────────────────────────────────────────────────────

VERIFY_SQL = """
-- Run these in Supabase SQL editor (https://supabase.com/dashboard/project/oynfhdqizebvgmaoiuax/sql)
-- after the script completes. Each should return the expected count.

-- 7 investors
SELECT COUNT(*) AS investors FROM investors WHERE email LIKE 'sahilmhl25+demo-%';

-- 5 LLPs + 5 default projects
SELECT COUNT(*) AS llps     FROM llps     WHERE name LIKE '%-demo';
SELECT COUNT(*) AS projects FROM projects WHERE name LIKE '%-demo';

-- 7 allocations + 5 payouts (F-ALC-03 has no payout, F-ALC-02 has 1, etc.)
SELECT COUNT(*) AS investor_units FROM investor_units
  WHERE zoho_allocation_id LIKE '11691010000014%';

SELECT COUNT(*) AS payouts FROM payouts WHERE utr LIKE 'DEMOUTR%';

-- Webhook log audit (manual_resync entries)
SELECT event_type, status, COUNT(*)
FROM webhook_log
WHERE source = 'manual_resync'
GROUP BY 1, 2
ORDER BY 1;
"""


# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

def main() -> int:
    global LOG_PATH

    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--env-file", default=".env.local", help="Path to .env file (default .env.local)")
    p.add_argument("--dry-run", action="store_true", help="Print actions without making HTTP calls")
    p.add_argument("--only", choices=["investors", "llps", "allocations"], help="Run only one phase")
    p.add_argument("--inline-records", action="store_true", help="Use bundled fixture data (don't fetch from Zoho — recommended)")
    args = p.parse_args()

    here = Path(__file__).parent
    LOG_PATH = here / f"sync_run_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log"
    log(f"LOG: {LOG_PATH}")

    env = load_env(here / args.env_file)
    if not env.get("SUPABASE_URL"):
        log("ERROR: SUPABASE_URL missing")
        return 1
    log(f"SUPABASE_URL = {env['SUPABASE_URL']}")
    log(f"ADMIN_SECRET set:        {bool(env.get('ADMIN_SECRET'))}")
    log(f"ADMIN_RESYNC_SECRET set: {bool(env.get('ADMIN_RESYNC_SECRET'))}")
    log(f"DRY RUN: {args.dry_run}")

    # Run phases in order, unless --only specified.
    results: dict[str, list] = {}
    phases = ["investors", "llps", "allocations"] if not args.only else [args.only]
    for phase in phases:
        if phase == "investors":
            results["investors"] = phase_investors(env, args.dry_run)
        elif phase == "llps":
            results["llps"] = phase_llps(env, args.dry_run)
        elif phase == "allocations":
            results["allocations"] = phase_allocations(env, args.dry_run)

    # Summary
    log("\n══════ SUMMARY ══════")
    for phase, rows in results.items():
        ok = sum(1 for _, st, _ in rows if 200 <= st < 300)
        bad = len(rows) - ok
        log(f"  {phase:<14} OK={ok}  FAIL={bad}")

    log("\n══════ VERIFICATION SQL ══════")
    log(VERIFY_SQL)

    # Exit non-zero if any failures
    any_fail = any(st < 200 or st >= 300 for rs in results.values() for _, st, _ in rs)
    return 1 if any_fail else 0


if __name__ == "__main__":
    sys.exit(main())
