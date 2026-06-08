
-- Phase 2A: Create private storage buckets
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES
  ('arl-documents', 'arl-documents', false, 52428800, ARRAY['application/pdf','image/jpeg','image/png','image/webp']),
  ('arl-gallery',   'arl-gallery',   false, 10485760, ARRAY['image/jpeg','image/png','image/webp'])
ON CONFLICT (id) DO NOTHING;

-- Storage RLS: arl-documents
-- Investors can only read their own documents (path: documents/{investor_id}/...)
CREATE POLICY "investors read own documents"
ON storage.objects FOR SELECT
TO authenticated
USING (
  bucket_id = 'arl-documents'
  AND (storage.foldername(name))[1] = 'documents'
  AND (storage.foldername(name))[2] = (
    SELECT id::text FROM public.investors WHERE id = (SELECT auth.uid())
  )
);

-- Edge Functions (service role) write to arl-documents
CREATE POLICY "service role full access arl-documents"
ON storage.objects
TO service_role
USING (bucket_id = 'arl-documents')
WITH CHECK (bucket_id = 'arl-documents');

-- Storage RLS: arl-gallery
-- Investors can read gallery photos only for projects they have units in
CREATE POLICY "investors read gallery for their projects"
ON storage.objects FOR SELECT
TO authenticated
USING (
  bucket_id = 'arl-gallery'
  AND (storage.foldername(name))[2] IN (
    SELECT project_id::text FROM public.investor_units
    WHERE investor_id = (SELECT auth.uid())
  )
);

-- Edge Functions (service role) write to arl-gallery
CREATE POLICY "service role full access arl-gallery"
ON storage.objects
TO service_role
USING (bucket_id = 'arl-gallery')
WITH CHECK (bucket_id = 'arl-gallery');
