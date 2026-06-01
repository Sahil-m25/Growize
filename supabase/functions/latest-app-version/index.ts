// latest-app-version — returns the latest published Growize APK release.
//
// Used by the Flutter app on launch to decide whether to render the
// "new version available" banner. Reads the `app_releases` table and
// returns the row with the highest version_code. Graceful: if there
// are no rows yet, returns `{ version_code: 0 }` and HTTP 200 so the
// client treats itself as up-to-date.
//
// Auth: anonymous access allowed (verify_jwt=false). The version
// check should work pre-login on a cold start.
//
// Response shape:
//   {
//     version_code: number,
//     version_name: string,
//     apk_url: string | null,
//     web_url: string | null,
//     release_notes: string | null,
//     is_critical: boolean
//   }

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders, preflight } from "../_shared/cors.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const EMPTY_RESPONSE = {
  version_code: 0,
  version_name: "",
  apk_url: null,
  web_url: null,
  release_notes: null,
  is_critical: false,
};

function jsonResponse(
  req: Request,
  body: unknown,
  init: ResponseInit = {},
): Response {
  return new Response(JSON.stringify(body), {
    ...init,
    headers: {
      ...corsHeaders(req),
      "content-type": "application/json",
      "cache-control": "no-store",
      ...(init.headers ?? {}),
    },
  });
}

Deno.serve(async (req: Request) => {
  const pf = preflight(req);
  if (pf) return pf;

  // Service-role client so we can read regardless of caller's JWT
  // (function is invoked unauthenticated for cold-start checks).
  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  try {
    const { data, error } = await supabase
      .from("app_releases")
      .select(
        "version_code, version_name, apk_url, web_url, release_notes, is_critical",
      )
      .order("version_code", { ascending: false })
      .limit(1)
      .maybeSingle();

    if (error) {
      console.error("latest-app-version query failed", error);
      // Fail soft — return empty so the app doesn't nag.
      return jsonResponse(req, EMPTY_RESPONSE, { status: 200 });
    }

    if (!data) {
      return jsonResponse(req, EMPTY_RESPONSE, { status: 200 });
    }

    return jsonResponse(req, {
      version_code: data.version_code,
      version_name: data.version_name,
      apk_url: data.apk_url,
      web_url: data.web_url,
      release_notes: data.release_notes,
      is_critical: Boolean(data.is_critical),
    });
  } catch (e) {
    console.error("latest-app-version unexpected error", e);
    return jsonResponse(req, EMPTY_RESPONSE, { status: 200 });
  }
});
