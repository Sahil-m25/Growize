-- 074: investors can read any arl-gallery file that is catalogued in
-- gallery_photos for a project they hold units in, whatever its folder.
-- (The older policy only covered the gallery/<project_id>/ folder that
-- gallery-sync writes; dashboard uploads land at the bucket root.)
-- Applied live on 2026-09-27.
CREATE POLICY "investors read catalogued gallery photos" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'arl-gallery' AND EXISTS (
    SELECT 1 FROM public.gallery_photos g
    JOIN public.investor_units iu ON iu.project_id = g.project_id
    WHERE g.storage_path = storage.objects.name
      AND iu.investor_id = (SELECT auth.uid())));
