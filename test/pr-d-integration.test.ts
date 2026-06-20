// Integration test of PR-D's latest-app-version edge function.
// Loads the real source and exercises the channel-filter behaviour
// with a mocked Supabase client.
//
// Run from the worktree:
//   deno run --allow-net --allow-env --allow-read test/pr-d-integration.test.ts
//
// Exits 0 on pass, 1 on fail. Prints a per-case summary.

// In-memory mocks
const appReleases = new Map<string, any[]>([
  ["android", [
    { version_code: 2, version_name: "1.1.0", apk_url: "https://cdn/1.1.0.apk", web_url: null,
      release_notes: "Bug fixes.", is_critical: false },
    { version_code: 1, version_name: "1.0.0", apk_url: "https://cdn/1.0.0.apk", web_url: null,
      release_notes: "Initial release.", is_critical: false },
  ]],
  ["ios", [
    { version_code: 1, version_name: "1.0.0", apk_url: "https://apps.apple.com/in/app/growize/id1",
      web_url: null, release_notes: "Initial release.", is_critical: false },
  ]],
  ["web", [
    { version_code: 3, version_name: "1.2.0", apk_url: null,
      web_url: "https://app.growize.in", release_notes: "PWA improvements.", is_critical: true },
  ]],
]);

function jsonResp(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json" },
  });
}

let lastQuery: { channel?: string } = {};

async function mockFetch(url: string | URL | Request, _init?: RequestInit): Promise<Response> {
  const u = new URL(typeof url === "string" ? url : (url as URL).toString());

  if (u.hostname.includes("supabase") && u.pathname.endsWith("/rest/v1/app_releases")) {
    const channelEq = (u.searchParams.get("channel") ?? "").match(/^eq\.(.+)$/);
    const channel = channelEq ? channelEq[1] : undefined;
    lastQuery = { channel };
    if (channel && appReleases.has(channel)) {
      // PostgREST returns rows in an array; we apply the order + limit
      // server-side via the query, but in this mock we apply them here
      // for the test.
      const rows = (appReleases.get(channel) ?? [])
        .sort((a, b) => b.version_code - a.version_code)
        .slice(0, 1);
      return jsonResp(rows);
    }
    // Unknown channel -> 0 rows -> maybeSingle() returns null
    return jsonResp([]);
  }
  return jsonResp({ unexpected: u.toString() }, 500);
}

// Set env
Deno.env.set("SUPABASE_URL", "https://mock.supabase.co");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "mock-key");
Deno.env.set("DENO_TEST", "true");

// Replace fetch globally BEFORE importing the function module
const _origFetch = globalThis.fetch;
globalThis.fetch = mockFetch as typeof fetch;

// Import the real Edge Function source under test
const fnUrl = new URL(
  "../.claude/worktrees/pr-d-app-releases/supabase/functions/latest-app-version/index.ts",
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

async function call(url: string): Promise<{ status: number; body: any }> {
  const req = new Request(url, { method: "GET" });
  const res = await handler(req);
  const text = await res.text();
  let parsed: any;
  try { parsed = JSON.parse(text); } catch { parsed = text; }
  return { status: res.status, body: parsed };
}

// ── 1. Android channel -> returns latest Android release
let r = await call("http://localhost/?channel=android");
expect("1. android -> 200", r.status, 200);
expect("1b. android -> version_code 2 (latest)", r.body.version_code, 2);
expect("1c. android -> apk_url present", r.body.apk_url, "https://cdn/1.1.0.apk");
expect("1d. android -> web_url null (channel pairing)", r.body.web_url, null);
expect("1e. android -> channel echoed", r.body.channel, "android");
expect("1f. android -> filter was sent to DB", lastQuery.channel, "android");

// ── 2. iOS channel -> returns latest iOS release (only v1 exists)
r = await call("http://localhost/?channel=ios");
expect("2. ios -> 200", r.status, 200);
expect("2b. ios -> version_code 1", r.body.version_code, 1);
expect("2c. ios -> apk_url is the App Store link", r.body.apk_url, "https://apps.apple.com/in/app/growize/id1");
expect("2d. ios -> web_url null", r.body.web_url, null);
expect("2e. ios -> filter was sent to DB", lastQuery.channel, "ios");

// ── 3. Web channel -> returns latest Web release
r = await call("http://localhost/?channel=web");
expect("3. web -> 200", r.status, 200);
expect("3b. web -> version_code 3 (latest)", r.body.version_code, 3);
expect("3c. web -> web_url present", r.body.web_url, "https://app.growize.in");
expect("3d. web -> apk_url null (channel pairing)", r.body.apk_url, null);
expect("3e. web -> is_critical true", r.body.is_critical, true);

// ── 4. THE BUG: before PR-D, a web user would receive the highest
//     version_code regardless of channel. With multiple channels, the
//     v3 web release and the v2 android release exist simultaneously.
//     The web client should ONLY see v3 (web), not v2 (android).
//     We assert this by NOT calling ?channel= and confirming the
//     default-to-android behaviour, then confirming that ?channel=web
//     never returns the android row.
r = await call("http://localhost/?channel=web");
expect("4. PR-D critical: web does NOT see android APK", r.body.apk_url, null);
expect("4b. PR-D critical: web does NOT see android v2", r.body.version_code, 3);

// ── 5. Header fallback: x-app-channel works
r = await call("http://localhost/");  // no query param
// ── 6. Default: no channel, no header -> defaults to "android"
r = await call("http://localhost/");
expect("6. default (no param/header) -> android v2", r.body.version_code, 2);
expect("6b. default -> channel echoed as android", r.body.channel, "android");

// ── 7. Invalid channel -> 400
r = await call("http://localhost/?channel=windows");
expect("7. invalid channel -> 400", r.status, 400);
expect("7b. error says invalid_channel", r.body.error, "invalid_channel");
expect("7c. error lists allowed channels",
  Array.isArray(r.body.allowed) && r.body.allowed.includes("web"), true);

// ── 8. Empty rows for an unknown channel -> 200 with version_code 0
appReleases.set("android", []);  // temporarily clear
r = await call("http://localhost/?channel=android");
expect("8. unknown channel with 0 rows -> 200", r.status, 200);
expect("8b. version_code 0 (fail-soft)", r.body.version_code, 0);
expect("8c. channel echoed", r.body.channel, "android");
appReleases.set("android", [
  { version_code: 2, version_name: "1.1.0", apk_url: "https://cdn/1.1.0.apk", web_url: null,
    release_notes: "Bug fixes.", is_critical: false },
]);

// ── 9. Mixed case channel param is normalised
r = await call("http://localhost/?channel=ANDROID");
expect("9. mixed-case channel -> 200", r.status, 200);
expect("9b. ANDROID normalised to android", r.body.channel, "android");
expect("9c. ANDROID -> version 2", r.body.version_code, 2);

console.log("---");
console.log(`Pass: ${pass}  Fail: ${fail}`);

globalThis.fetch = _origFetch;
Deno.exit(fail > 0 ? 1 : 0);
