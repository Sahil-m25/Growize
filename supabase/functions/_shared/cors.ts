// Shared CORS helpers for ARL edge functions.
//
// Origin allow-listing replaces the pre-launch `Access-Control-Allow-Origin: *`
// posture (audit finding S-005, docs/security_audit_2026-05-13.md). The
// allow-list is read from the `APP_ALLOWED_ORIGINS` environment variable
// (comma-separated origins, no spaces). A request's `Origin` header is
// matched against the list and, on match, echoed back as the
// `Access-Control-Allow-Origin` value — never `*`. A `Vary: Origin`
// header is always included so any caching layer keys on the origin.
//
// Patterns supported in the allow-list:
//   * Exact match: "https://app.agresearchlabs.com"
//   * Localhost-port wildcard: "http://localhost:*" matches any port,
//     so `flutter run -d chrome` (random ports each launch) works.
//
// Server-to-server callers (Zoho webhook, pg_cron) don't send `Origin`
// at all — in that case no `Allow-Origin` header is set, which is fine
// because CORS only applies in a browser.
//
// Set the env var (one-time):
//   supabase secrets set APP_ALLOWED_ORIGINS=https://app.agresearchlabs.com,http://localhost:*

const ALLOW_METHODS = "POST, OPTIONS";
const ALLOW_HEADERS =
  "authorization, x-client-info, apikey, content-type, " +
  "x-arl-admin-secret, x-arl-webhook-secret, x-arl-cron-secret";

function parseAllowList(): string[] {
  return (Deno.env.get("APP_ALLOWED_ORIGINS") ?? "")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
}

function matchOrigin(origin: string, list: string[]): string | null {
  if (!origin) return null;
  for (const pattern of list) {
    if (pattern === origin) return origin;
    if (pattern.endsWith(":*")) {
      const prefix = pattern.slice(0, -2);
      if (origin.startsWith(prefix + ":")) return origin;
    }
  }
  return null;
}

export function corsHeaders(req: Request): Record<string, string> {
  const list = parseAllowList();
  const origin = req.headers.get("Origin") ?? "";
  const allowed = matchOrigin(origin, list);
  const headers: Record<string, string> = {
    "Access-Control-Allow-Methods": ALLOW_METHODS,
    "Access-Control-Allow-Headers": ALLOW_HEADERS,
    "Vary": "Origin",
  };
  if (allowed) {
    headers["Access-Control-Allow-Origin"] = allowed;
    headers["Access-Control-Allow-Credentials"] = "true";
  }
  return headers;
}

export function preflight(req: Request): Response | null {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders(req) });
  }
  return null;
}

export function jsonResponse(
  req: Request,
  body: unknown,
  init: ResponseInit = {},
): Response {
  return new Response(JSON.stringify(body), {
    ...init,
    headers: {
      ...corsHeaders(req),
      "content-type": "application/json",
      ...(init.headers ?? {}),
    },
  });
}
