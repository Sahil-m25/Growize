-- 075: "started" copy for Core Civil reads as ongoing work.
-- Applied live on 2026-09-28. (EKA milestone dates and the Civil photo
-- were set as data on project_phases: phase_date 3 Sep / 15 Sep / 27 Sep,
-- image_url = a path in the private arl-gallery bucket; the sync trigger
-- re-dated and re-titled the matching updates and notifications.)
UPDATE public.phase_copy
   SET started_title = 'Civil work in progress',
       started_body  = 'Core civil work is in progress at {project}: excavation and foundations are underway.',
       updated_at    = now()
 WHERE stage_index = 3;
