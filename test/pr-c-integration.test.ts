// Integration test of PR-C's notify-consultation-request edge function.
// Loads the real source and exercises the Slack-notification flow with
// a mocked Supabase client + Slack POST.
//
// Run from the worktree:
//   deno run --allow-net --allow-env --allow-read test/pr-c-integration.test.ts
//
// Exits 0 on pass, 1 on fail. Prints a per-case summary.

// In-memory mocks
const consultationRows = new Map<string, any>([
  ["c-existing", {
    id: "c-existing",
    user_id: "investor-uuid-A",
    project_id: "project-uuid-1",
    units_requested: 5,
    message: "Test consultation",
    status: "new",
    created_at: "2026-06-13T00:00:00Z",
  }],
]);

const investors = new Map<string, any>([
  ["investor-uuid-A", { name: "Alice Investor", email: "alice@x.in", phone: "+91-99999-00001" }],
  ["investor-uuid-B", { name: "Bob Investor",   email: "bob@x.in",   phone: "+91-99999-00002" }],
]);

const projects = new Map<string, any>([
  ["project-uuid-1", { name: "Greenfield Farm 1", tier: "10L" }],
]);

let slackPostedBody: any = null;
let slackCallCount = 0;

function jsonResp(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json" },
  });
}

async function mockFetch(url: string | URL | Request, init?: RequestInit): Promise<Response> {
  const u = new URL(typeof url === "string" ? url : (url as URL).toString());

  // Slack POST
  if (u.hostname.includes("hooks.slack.com")) {
    slackCallCount++;
    slackPostedBody = JSON.parse(init?.body as string);
    return jsonResp({ ok: true });
  }

  // PostgREST: consultation_requests row lookup
  if (u.hostname.includes("supabase") && u.pathname.endsWith("/rest/v1/consultation_requests") && init?.method !== "POST") {
    const eq = (u.searchParams.get("id") ?? "").match(/^eq\.(.+)$/);
    const id = eq ? eq[1] : "";
    const row = consultationRows.get(id);
    return row ? jsonResp([row]) : jsonResp([]);
  }

  // PostgREST: projects row lookup
  if (u.hostname.includes("supabase") && u.pathname.endsWith("/rest/v1/projects") && init?.method !== "POST") {
    const eq = (u.searchParams.get("id") ?? "").match(/^eq\.(.+)$/);
    const id = eq ? eq[1] : "";
    const row = projects.get(id);
    return row ? jsonResp([row]) : jsonResp([]);
  }

  // PostgREST: investors row lookup (THE BUG FIX)
  if (u.hostname.includes("supabase") && u.pathname.endsWith("/rest/v1/investors") && init?.method !== "POST") {
    const eq = (u.searchParams.get("id") ?? "").match(/^eq\.(.+)$/);
    const id = eq ? eq[1] : "";
    const row = investors.get(id);
    return row ? jsonResp([row]) : jsonResp([]);
  }

  return jsonResp({ unexpected: u.toString() }, 500);
}

// Set env
Deno.env.set("SUPABASE_URL", "https://mock.supabase.co");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "mock-key");
Deno.env.set("SLACK_CONSULTATION_WEBHOOK_URL", "https://hooks.slack.com/services/T00/B00/XXX");
Deno.env.set("CRON_SECRET", "test-cron-secret");
Deno.env.set("DENO_TEST", "true");

// Replace fetch globally BEFORE importing the function module
const _origFetch = globalThis.fetch;
globalThis.fetch = mockFetch as typeof fetch;

// Import the real Edge Function source under test.
// Path is relative to the test file (test/pr-c-integration.test.ts) and
// points at the PR-C worktree's copy of the function.
const fnUrl = new URL(
  "../.claude/worktrees/pr-c-consultation-lookup/supabase/functions/notify-consultation-request/index.ts",
  import.meta.url,
).href;
const mod = await import(fnUrl);
const handler = mod.handler;

let pass = 0;
let fail = 0;
function expect(label: string, actual: unknown, expected: unknown) {
  const ok = actual === expected;
  console.log(`${ok ? "OK  " : "FAIL"} ${label}: got=${JSON.stringify(actual)} want=${JSON.stringify(expected)}`);
  if (ok) pass++;
  else fail++;
}

async function call(body: unknown, headers: Record<string, string> = {}): Promise<{ status: number; body: any }> {
  const req = new Request("http://127.0.0.1:54322/", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-arl-cron-secret": "test-cron-secret",
      ...headers,
    },
    body: JSON.stringify(body),
  });
  const res = await handler(req);
  const text = await res.text();
  let parsed: any;
  try { parsed = JSON.parse(text); } catch { parsed = text; }
  return { status: res.status, body: parsed };
}

// ── 1. Happy path: known consultation + known investor + known project
slackCallCount = 0;
slackPostedBody = null;
let r = await call({ consultation_request_id: "c-existing" });
expect("1. happy path -> 200", r.status, 200);
expect("1b. Slack was called once", slackCallCount, 1);

// ── 2. The actual bug fix: investor NAME must appear in the Slack message
//     (before PR-C: "from Unknown investor on Greenfield Farm 1")
//     (after  PR-C: "from Alice Investor on Greenfield Farm 1")
expect("2. Slack 'text' contains investor NAME", slackPostedBody?.text?.includes("Alice Investor"), true);
expect("2b. Slack 'text' contains project NAME", slackPostedBody?.text?.includes("Greenfield Farm 1"), true);

// ── 3. The investor EMAIL appears in a Slack block (before: empty)
//     The Contact field is one of the entries in the section's `fields`
//     array (not a top-level block.text), so we need to search across
//     every `fields` entry across every section block.
const allFieldTexts: string[] = [];
for (const b of (slackPostedBody?.blocks ?? []) as any[]) {
  if (Array.isArray(b.fields)) {
    for (const f of b.fields) {
      if (typeof f?.text === "string") allFieldTexts.push(f.text);
    }
  }
  if (typeof b?.text?.text === "string") allFieldTexts.push(b.text.text);
}
const contactConcat = allFieldTexts.join(" | ");
expect("3. Slack 'Contact' field contains email", contactConcat.includes("alice@x.in"), true);
expect("3b. Slack 'Contact' field contains phone", contactConcat.includes("+91-99999-00001"), true);

// ── 4. The investor FIELD in the Slack blocks shows the name
const fieldsBlocks = slackPostedBody?.blocks
  ?.find((b: any) => b.fields)?.fields ?? [];
const investorField = fieldsBlocks.find((f: any) =>
  f.text?.includes("Investor")
)?.text ?? "";
expect("4. Slack 'Investor' field shows the name", investorField.includes("Alice Investor"), true);

// ── 5. Auth gate: bad secret -> 401
slackCallCount = 0;
r = await call({ consultation_request_id: "c-existing" }, { "x-arl-cron-secret": "wrong" });
expect("5. bad cron secret -> 401", r.status, 401);
expect("5b. Slack NOT called on auth failure", slackCallCount, 0);

// ── 6. Missing id -> 400
r = await call({});
expect("6. missing consultation_request_id -> 400", r.status, 400);

// ── 7. Unknown consultation -> 404
r = await call({ consultation_request_id: "nonexistent" });
expect("7. unknown consultation -> 404", r.status, 404);

// ── 8. No Slack webhook URL configured -> returns 200 with "skipped" body,
//       does NOT call Slack (and does NOT fail the trigger — that's the contract)
Deno.env.set("SLACK_CONSULTATION_WEBHOOK_URL", "");
slackCallCount = 0;
r = await call({ consultation_request_id: "c-existing" });
expect("8. no Slack webhook -> 200 ok", r.status, 200);
expect("8b. Slack NOT called when URL unset", slackCallCount, 0);
Deno.env.set("SLACK_CONSULTATION_WEBHOOK_URL", "https://hooks.slack.com/services/T00/B00/XXX");

// ── 9. Investor with email but no phone — Slack should still render correctly
consultationRows.set("c-no-phone", {
  id: "c-no-phone", user_id: "investor-uuid-B",
  project_id: "project-uuid-1", units_requested: 1, message: "n/a",
  status: "new", created_at: "2026-06-13T00:00:00Z",
});
slackCallCount = 0;
slackPostedBody = null;
r = await call({ consultation_request_id: "c-no-phone" });
expect("9. investor with email but no phone -> 200", r.status, 200);
expect("9b. Slack shows Bob Investor", slackPostedBody?.text?.includes("Bob Investor"), true);
expect("9c. Slack shows bob@x.in", JSON.stringify(slackPostedBody).includes("bob@x.in"), true);

console.log("---");
console.log(`Pass: ${pass}  Fail: ${fail}`);

globalThis.fetch = _origFetch;
Deno.exit(fail > 0 ? 1 : 0);
