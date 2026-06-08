
-- ============================================================
-- MIGRATION 005 — GALLERY & DOCUMENTS
-- Gallery photos: polled from LLP_Creation_Module attachments
--   by gallery-sync Edge Function (daily cron).
--   zoho_file_id prevents duplicate syncs.
-- Documents: per-investor PDFs, polled from Contacts attachments.
--   Stored in Supabase Storage. App reads via signed URLs (1hr).
-- ============================================================

-- -------------------------------------------------------
-- GALLERY PHOTOS
-- Project-level (not investor-specific).
-- Investors see photos for projects they have units in (via RLS).
-- -------------------------------------------------------
CREATE TABLE public.gallery_photos (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id      UUID NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,

  -- Supabase Storage path: gallery/{project_id}/{zoho_file_id}.jpg
  storage_path    TEXT NOT NULL,
  zoho_file_id    TEXT UNIQUE NOT NULL,   -- prevents duplicate sync on re-poll

  caption         TEXT,
  unit_label      TEXT,                   -- e.g. "Unit 4" — which unit the photo shows
  taken_at        DATE,
  uploaded_at     TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE public.gallery_photos IS
  'Farm photos synced from LLP_Creation_Module attachments by gallery-sync cron. '
  'zoho_file_id ensures idempotent sync.';

CREATE INDEX idx_gallery_project_uploaded
  ON public.gallery_photos (project_id, uploaded_at DESC);

-- -------------------------------------------------------
-- DOCUMENTS
-- Investor-specific PDFs (contracts, agreements, KYC docs).
-- Stored in Supabase Storage under documents/{investor_id}/
-- Signed URLs generated at read time (1hr expiry).
-- -------------------------------------------------------
CREATE TABLE public.documents (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  investor_id     UUID NOT NULL REFERENCES public.investors(id) ON DELETE CASCADE,
  project_id      UUID REFERENCES public.projects(id) ON DELETE SET NULL, -- optional link

  -- Classification
  doc_type        TEXT NOT NULL DEFAULT 'other'
                    CHECK (doc_type IN ('contract','agreement','kyc','other')),
  name            TEXT NOT NULL,         -- display name e.g. "Investment Agreement - Pineapple Enterprises.pdf"

  -- Supabase Storage path: documents/{investor_id}/{zoho_file_id}.pdf
  storage_path    TEXT NOT NULL,
  zoho_file_id    TEXT UNIQUE,           -- prevents duplicate sync
  file_size_kb    INT,

  uploaded_at     TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE public.documents IS
  'Investor-specific documents. Stored in Supabase Storage. '
  'App reads via time-limited signed URLs — never direct Zoho Drive links.';

CREATE INDEX idx_documents_investor
  ON public.documents (investor_id, uploaded_at DESC);
