-- ============================================================
-- MIGRATION 026 — USER SETTINGS & LOGIN EVENTS
-- Backs the SecurityScreen in the Flutter app.
--   user_settings: one row per auth user — biometric toggle,
--     notifications toggle, app PIN hash (never plaintext).
--   login_events: append-only audit log written from client
--     after a successful Supabase sign-in.
-- ============================================================

-- -------------------------------------------------------
-- USER SETTINGS (per-user preferences + hashed app PIN)
-- One row per auth user. App PIN stored as hash + salt
-- only (PBKDF2-style SHA-256 iterations done client-side
-- before the row is written — the DB never sees plaintext).
-- -------------------------------------------------------
CREATE TABLE public.user_settings (
  user_id                UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  biometric_enabled      BOOLEAN NOT NULL DEFAULT FALSE,
  notifications_enabled  BOOLEAN NOT NULL DEFAULT TRUE,
  app_pin_hash           TEXT,     -- base64(sha256-iterated digest); NULL = not set
  app_pin_salt           TEXT,     -- base64(16 random bytes)
  app_pin_iterations     INT,      -- iteration count used when hash was computed
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.user_settings IS
  'Per-user app preferences and app PIN hash. PIN is hashed client-side '
  '(salt + N iterations of SHA-256). DB never receives plaintext PIN.';

CREATE TRIGGER trg_user_settings_updated_at
  BEFORE UPDATE ON public.user_settings
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.user_settings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "user_settings: read own row"
  ON public.user_settings FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY "user_settings: insert own row"
  ON public.user_settings FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "user_settings: update own row"
  ON public.user_settings FOR UPDATE
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

GRANT SELECT, INSERT, UPDATE ON public.user_settings TO authenticated;

-- -------------------------------------------------------
-- LOGIN EVENTS (audit log of successful sign-ins)
-- Append-only — no UPDATE/DELETE policy granted to users.
-- Written by the client on AuthChangeEvent.signedIn.
-- -------------------------------------------------------
CREATE TABLE public.login_events (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  occurred_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  device_label  TEXT,           -- e.g. "iPhone 15 Pro" or "Chrome on Windows"
  platform      TEXT,           -- "ios" | "android" | "web" | "windows" | "macos" | "linux"
  app_version   TEXT,           -- e.g. "1.0.0+1"
  user_agent    TEXT
);

COMMENT ON TABLE public.login_events IS
  'Audit log of successful sign-ins. Append-only from the client; '
  'no UPDATE/DELETE policies granted to investors. Powers the '
  'SecurityScreen login-history list and the "Last login" stamp.';

CREATE INDEX idx_login_events_user_time
  ON public.login_events (user_id, occurred_at DESC);

ALTER TABLE public.login_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "login_events: read own rows"
  ON public.login_events FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY "login_events: insert own row"
  ON public.login_events FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid());

GRANT SELECT, INSERT ON public.login_events TO authenticated;
