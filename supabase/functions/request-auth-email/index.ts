// request-auth-email — server-side gate for invite-only auth email flows
// (password reset + magic link).
//
// The Supabase Auth client APIs `resetPasswordForEmail` and
// `signInWithOtp` happily send an email to ANY address. That's fine
// for self-signup products but wrong for an invite-only investor
// portal: any visitor could discover that an email is registered
// (account enumeration) or spam our SMTP quota.
//
// This function:
//   1. Verifies the request came from our app (shared secret header)
//   2. Looks up the email in `public.investors` AND `auth.users`
//      (service role; bypasses RLS)
//   3. If linked: triggers the matching Supabase Auth flow which
//      sends the email via the Supabase built-in SMTP.
//   4. If not linked: sleeps a small constant delay, then returns
//      the same `{ok:true}` response as the happy path — no signal
//      to the caller that the email is unregistered.
//
// Auth: `x-arl-cron-secret` header matching `ARL_AUTH_GATE_SECRET`
//       env var. Separate from CRON_SECRET so the value shipped
//       inside the Flutter binary can be rotated without breaking
//       DB-trigger-fired functions.
//
// Deploy:
//   supabase functions deploy request-auth-email --no-verify-jwt
// Secrets:
//   supabase secrets set ARL_AUTH_GATE_SECRET=<random 32+ chars>

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let r = 0;
  for (let i = 0; i < a.length; i++) {
    r |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return r === 0;
}

function ok(): Response {
  return new Response(JSON.stringify({ ok: true }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
}

// Constant-time pad so the no-op branch takes roughly as long as the
// happy path (which talks to GoTrue + SMTP). Without this, a caller
// could distinguish "registered" from "unregistered" via response
// latency alone.
async function timingPad(): Promise<void> {
  await new Promise((r) => setTimeout(r, 350));
}

interface ReqBody {
  email?: unknown;
  mode?: unknown;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "method_not_allowed" }), {
      status: 405,
      headers: { "Content-Type": "application/json" },
    });
  }

  // ── Shared-secret gate ────────────────────────────────────────────
  const expected = Deno.env.get("ARL_AUTH_GATE_SECRET");
  const got = req.headers.get("x-arl-cron-secret") ?? "";
  if (!expected || !timingSafeEqual(got, expected)) {
    return new Response(JSON.stringify({ error: "unauthorized" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  let body: ReqBody;
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "invalid_body" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  const emailRaw = typeof body.email === "string" ? body.email : "";
  const email = emailRaw.trim().toLowerCase();
  const mode = body.mode;
  if (mode !== "reset" && mode !== "magic_link") {
    return new Response(JSON.stringify({ error: "invalid_mode" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  // Basic shape check — reject obviously malformed inputs before
  // they hit the DB. Don't echo the email back in the error.
  if (email.length < 3 || email.length > 254 || !email.includes("@")) {
    // Still return 200 to match the no-op branch — don't reveal that
    // the validator caught this either.
    await timingPad();
    return ok();
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  // ── Gate: must exist in investors with a linked auth user ────────
  // Service role bypasses RLS. We deliberately do not log the email.
  const { data: investor, error: invErr } = await supabase
    .from("investors")
    .select("user_id")
    .eq("email", email)
    .maybeSingle();

  if (invErr) {
    console.error("investor lookup failed", { code: invErr.code });
    // Don't leak details — return 200 anyway, but log internally.
    await timingPad();
    return ok();
  }

  const userId = investor?.user_id as string | undefined;
  if (!userId) {
    await timingPad();
    return ok();
  }

  // Confirm the linked auth user actually exists. Catches the edge
  // case where an investor row was created but the auth user was
  // later deleted manually.
  const { data: userResp, error: userErr } = await supabase.auth.admin
    .getUserById(userId);
  if (userErr || !userResp?.user) {
    await timingPad();
    return ok();
  }

  // ── Trigger the matching Supabase Auth flow ──────────────────────
  // Both methods are available on the service-role client and will
  // send via the configured SMTP. We swallow errors and still return
  // 200 — surfacing them would let a caller distinguish failure
  // modes (e.g. SMTP down vs rate-limit vs unknown email).
  try {
    if (mode === "reset") {
      const redirectTo = Deno.env.get("AUTH_RESET_REDIRECT_URL") || undefined;
      const { error } = await supabase.auth.resetPasswordForEmail(
        email,
        redirectTo ? { redirectTo } : undefined,
      );
      if (error) {
        console.error("reset send failed", { code: error.status });
      }
    } else {
      // magic_link
      const { error } = await supabase.auth.signInWithOtp({
        email,
        options: {
          // Belt + braces: even if the email lookup above were
          // somehow bypassed, refuse to create a brand-new user.
          shouldCreateUser: false,
        },
      });
      if (error) {
        console.error("magic_link send failed", { code: error.status });
      }
    }
  } catch (e) {
    console.error("send threw", { name: (e as Error).name });
  }

  return ok();
});
