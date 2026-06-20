// Integration test of PR-A's bank-change-request edge function.
// Spins up the real Deno-served function with a mocked fetch (no real
// DB or email calls). Run from the worktree with:
//
//   deno run --allow-net --allow-env --allow-read test/pr-a-integration.test.ts
//
// Exits 0 on pass, 1 on fail. Prints a per-case summary.

// In-memory mocks
const investors = new Map([
  ["verified-investor-uuid", { kyc_status: "verified", name: "Verified Investor", arl_id: "ARL-001" }],
  ["pending-investor-uuid",  { kyc_status: "pending",  name: "Pending Investor",  arl_id: "ARL-002" }],
  ["rejected-investor-uuid", { kyc_status: "rejected", name: "Rejected Investor", arl_id: "ARL-003" }],
]);

const bankChangeRequests: any[] = [];

function jsonResp(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json" },
  });
}

async function mockFetch(url: string | URL | Request, init?: RequestInit): Promise<Response> {
  const u = new URL(typeof url === "string" ? url : (url as URL).toString());
  // supabase.auth.getUser
  if (u.hostname.includes("supabase") && u.pathname.includes("/auth/v1/user")) {
    const auth = (init?.headers as Record<string, string> | undefined)?.Authorization ?? "";
    const token = auth.replace(/^Bearer\s+/i, "");
    if (token === "verified-jwt") return jsonResp({ id: "verified-investor-uuid", email: "v@x.in" });
    if (token === "pending-jwt")  return jsonResp({ id: "pending-investor-uuid",  email: "p@x.in" });
    if (token === "rejected-jwt") return jsonResp({ id: "rejected-investor-uuid", email: "r@x.in" });
    return jsonResp({ error: "bad token" }, 401);
  }
  // PostgREST: investors KYC lookup
  if (u.hostname.includes("supabase") && u.pathname.endsWith("/rest/v1/investors") && init?.method !== "POST") {
    const eq = (u.searchParams.get("id") ?? "").match(/^eq\.(.+)$/);
    const investorId = eq ? eq[1] : "";
    const inv = investors.get(investorId);
    return inv ? jsonResp([inv]) : jsonResp([]);
  }
  // PostgREST: bank_change_requests cooldown
  if (u.hostname.includes("supabase") && u.pathname.includes("/rest/v1/bank_change_requests") && (init?.method === "GET" || !init?.method)) {
    return jsonResp([]);
  }
  // PostgREST: bank_change_requests insert
  if (u.hostname.includes("supabase") && u.pathname.includes("/rest/v1/bank_change_requests") && init?.method === "POST") {
    const body = JSON.parse(init.body as string);
    const row = { id: `req-${bankChangeRequests.length + 1}`, ...body };
    bankChangeRequests.push(row);
    return jsonResp([row], 201);
  }
  // Resend
  if (u.hostname.includes("resend.com")) return jsonResp({ id: "email-1" }, 200);
  return jsonResp({ unexpected: u.toString() }, 500);
}

// Set env
Deno.env.set("SUPABASE_URL", "https://mock.supabase.co");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "mock-key");
Deno.env.set("ARL_OPS_EMAIL", "ops-test@arl.local");
Deno.env.set("RESEND_API_KEY", "mock-resend");
Deno.env.set("SENTRY_EDGE_DSN", "");  // disable Sentry for the test
Deno.env.set("DENO_TEST", "true");    // suppress auto-serve in the imported module

// Replace fetch globally BEFORE importing the function module
const _origFetch = globalThis.fetch;
globalThis.fetch = mockFetch as typeof fetch;

// Import the real Edge Function source under test.
// Path is relative to the test file (test/pr-a-integration.test.ts) and
// points at the PR-A worktree's copy of the function.
const fnUrl = new URL(
  "../.claude/worktrees/pr-a-bank-change/supabase/functions/bank-change-request/index.ts",
  import.meta.url,
).href;
const mod = await import(fnUrl);
const handler = mod.handler;

const PORT = 54322;

let pass = 0;
let fail = 0;
function expect(label: string, actual: unknown, expected: unknown) {
  const ok = actual === expected;
  console.log(`${ok ? "OK  " : "FAIL"} ${label}: got=${actual} want=${expected}`);
  if (ok) pass++;
  else fail++;
}

async function call(body: unknown, jwt = "verified-jwt"): Promise<{ status: number; body: any }> {
  const req = new Request(`http://127.0.0.1:${PORT}/`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${jwt}`,
      "Origin": "http://localhost:54321",
    },
    body: JSON.stringify(body),
  });
  const res = await handler(req);
  const text = await res.text();
  let parsed: any;
  try { parsed = JSON.parse(text); } catch { parsed = text; }
  return { status: res.status, body: parsed };
}

const goodBody = {
  bank_name: "HDFC Bank",
  account_masked: "XXXX-XXXX-1234",
  ifsc: "HDFC0001234",
  holder_name: "Verified Investor",
};

// ── Happy path
let r = await call(goodBody);
expect("1. happy path (verified KYC, valid inputs)", r.status, 200);
console.log("     body:", JSON.stringify(r.body));

// ── Empty fields
r = await call({ bank_name: "", account_masked: "", ifsc: "", holder_name: "" });
expect("2. empty fields -> 400", r.status, 400);

// ── Non-string field
r = await call({ bank_name: 12345, account_masked: "XXXX-XXXX-1234", ifsc: "HDFC0001234", holder_name: "X" });
expect("3. non-string field -> 400", r.status, 400);

// ── holder_name too long
r = await call({ ...goodBody, holder_name: "X".repeat(101) });
expect("4. holder_name 101 chars -> 400", r.status, 400);
console.log("     body:", JSON.stringify(r.body));

// ── bank_name too long
r = await call({ ...goodBody, bank_name: "X".repeat(81) });
expect("5. bank_name 81 chars -> 400", r.status, 400);

// ── ifsc too long
r = await call({ ...goodBody, ifsc: "X".repeat(12) });
expect("6. ifsc 12 chars -> 400", r.status, 400);

// ── Bad IFSC format
r = await call({ ...goodBody, ifsc: "hdfc123" });
expect("7. bad IFSC format -> 400", r.status, 400);
console.log("     body:", JSON.stringify(r.body));

// ── Bad IFSC (5th char not 0)
r = await call({ ...goodBody, ifsc: "HDFC1001234" });
expect("8. IFSC 5th char not 0 -> 400", r.status, 400);

// ── IFSC mixed case -> 200, stored as upper
r = await call({ ...goodBody, ifsc: "hdfc0001234" });
expect("9. IFSC mixed case -> 200 (canonicalised)", r.status, 200);
const lastInsert = bankChangeRequests[bankChangeRequests.length - 1];
if (lastInsert?.new_ifsc === "HDFC0001234") {
  console.log("OK   9b. IFSC stored as upper-case:", lastInsert.new_ifsc);
  pass++;
} else {
  console.log("FAIL 9b. IFSC not canonicalised:", lastInsert?.new_ifsc);
  fail++;
}

// ── Unmasked account number
r = await call({ ...goodBody, account_masked: "12345678901234" });
expect("10. raw account number -> 400", r.status, 400);

// ── KYC pending -> 403
r = await call(goodBody, "pending-jwt");
expect("11. KYC pending -> 403", r.status, 403);
console.log("     body:", JSON.stringify(r.body));

// ── KYC rejected -> 403
r = await call(goodBody, "rejected-jwt");
expect("12. KYC rejected -> 403", r.status, 403);

// ── No auth -> 401
r = await call(goodBody, "");
expect("13. no Authorization header -> 401", r.status, 401);

// ── Bad JWT -> 401
r = await call(goodBody, "garbage-jwt");
expect("14. invalid JWT -> 401", r.status, 401);

// ── Method not allowed
const r2 = await handler(new Request(`http://127.0.0.1:${PORT}/`, { method: "GET" }));
expect("15. GET method -> 405", r2.status, 405);

// ── OPTIONS preflight -> 200
const r3 = await handler(new Request(`http://127.0.0.1:${PORT}/`, {
  method: "OPTIONS",
  headers: { "Origin": "http://localhost:54321" },
}));
expect("16. OPTIONS preflight -> 200", r3.status, 200);

// ── Whitespace trimming
r = await call({ ...goodBody, bank_name: "  HDFC Bank  " });
expect("17. trimmed bank_name -> 200", r.status, 200);
const lastTrim = bankChangeRequests[bankChangeRequests.length - 1];
if (lastTrim?.new_bank_name === "HDFC Bank") {
  console.log("OK   17b. bank_name trimmed in storage:", JSON.stringify(lastTrim.new_bank_name));
  pass++;
} else {
  console.log("FAIL 17b. bank_name not trimmed:", JSON.stringify(lastTrim?.new_bank_name));
  fail++;
}

console.log("---");
console.log(`Pass: ${pass}  Fail: ${fail}`);
console.log(`Bank-change requests recorded: ${bankChangeRequests.length}`);

globalThis.fetch = _origFetch;
Deno.exit(fail > 0 ? 1 : 0);
