// Service-role Supabase client for Edge Functions. Bypasses RLS — only
// use this from server code that has already validated the caller.
import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

let _admin: SupabaseClient | null = null;

export function adminClient(): SupabaseClient {
  if (_admin) return _admin;
  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) {
    throw new Error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY");
  }
  _admin = createClient(url, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  return _admin;
}

/// Returns the user-scoped client built from the inbound JWT. Use this
/// when you want RLS enforced on writes (e.g. the user is creating
/// their own ticket and we want investor_id to be auto-set via RLS).
export function userClient(req: Request): SupabaseClient {
  const url = Deno.env.get("SUPABASE_URL");
  const anon = Deno.env.get("SUPABASE_ANON_KEY");
  if (!url || !anon) throw new Error("Missing SUPABASE_URL or SUPABASE_ANON_KEY");
  const auth = req.headers.get("Authorization") ?? "";
  return createClient(url, anon, {
    global: { headers: { Authorization: auth } },
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

/// Returns the auth.uid() of the caller, or null if no valid JWT.
export async function callerUserId(req: Request): Promise<string | null> {
  const client = userClient(req);
  const { data, error } = await client.auth.getUser();
  if (error || !data.user) return null;
  return data.user.id;
}
