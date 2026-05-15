# Documents — Ops Runbook

Audience: ops engineer (non-developer) operating the ARL Investor Portal day
to day. You will use Supabase Studio (SQL editor + Storage UI) for everything
in this doc. You do not need to touch the Flutter app, the migrations, or any
Edge Function code. If you see something here that doesn't match reality, log
a P1 and stop.

Project: Growize / ARL Investor Portal
Supabase project ID: `oynfhdqizebvgmaoiuax`
Storage bucket: `arl-documents` (private)
Backing migrations: `032_documents_tiering_schema.sql`,
`033_documents_tiering_rls.sql`

---

## 1. Intent

The portal has three document tiers, named by who can see them:

| Tier       | Visible to                                             | Typical content                                      |
|------------|--------------------------------------------------------|------------------------------------------------------|
| `common`   | every signed-in investor                               | company prospectus, brochure, sample agreement       |
| `project`  | investors who hold units in the referenced project     | project land deed, crop reports, project agreement   |
| `investor` | one specific investor only                             | their KYC packet, their personal contract, NDA       |

The Documents screen in the Flutter app renders three accordions in this fixed
order: Common, My Projects, My Documents. Empty sections still render with a
"No documents in this section yet." placeholder; the section headers never
disappear.

---

## 2. Mental model

Two things must agree for an investor to actually open a file:

1. A row in `public.documents` (the catalog entry) — controls whether the row
   is **listed** in the app.
2. An object in the `arl-documents` bucket at the matching storage path —
   controls whether the bytes can be **downloaded** when the investor taps the
   eye icon.

Either alone is useless. A row with no file = broken link. A file with no row
= invisible to the app.

### Storage path convention

The `documents.storage_path` column must match the object key in the
`arl-documents` bucket exactly. The expected key shape per tier:

```
common/<filename>
project/<project_id>/<filename>
investor/<auth_uid>/<filename>
```

Note: investor `auth_uid` and the `investors.id` are the **same UUID** by
design — every investor row has a primary key equal to their `auth.users.id`.
So `investor/<investor_id>/...` works too.

### RLS predicate per tier

Both the DB table `public.documents` and `storage.objects` filtered by
`bucket_id='arl-documents'` use the same logic, just expressed in two places:

| Tier       | Read predicate (paraphrased)                                                                 |
|------------|----------------------------------------------------------------------------------------------|
| `common`   | any authenticated user                                                                       |
| `project`  | `auth.uid()` appears in `investor_units` with the row's / path's `project_id`                |
| `investor` | `auth.uid()` equals the row's `investor_id` / the path's second folder component            |

Only investor-tier rows can be INSERTed by the app session. Common and project
tier inserts must come from `service_role` (Studio SQL editor counts as
service_role) or an Edge Function with the service-role key.

---

## 3. Schema (relevant columns)

`public.documents` columns currently in production:

| Column           | Type        | Nullable | Notes                                                    |
|------------------|-------------|----------|----------------------------------------------------------|
| `id`             | uuid        | NO       | default `gen_random_uuid()`                              |
| `investor_id`    | uuid        | YES      | required when `visibility='investor'`                    |
| `project_id`     | uuid (FK)   | YES      | required when `visibility='project'`; FK `projects.id`   |
| `doc_type`       | text        | NO       | one of: `contract`, `agreement`, `kyc`, `other`          |
| `name`           | text        | NO       | display name shown in the app                            |
| `storage_path`   | text        | NO       | object key in `arl-documents` bucket                     |
| `zoho_file_id`   | text        | YES      | Zoho CRM link if synced from there                       |
| `file_size_kb`   | int         | YES      | shown in app meta line; safe to leave NULL               |
| `uploaded_at`    | timestamptz | YES      | default `now()`; drives sort order                       |
| `visibility`     | text        | NO       | one of: `common`, `project`, `investor`; default investor|

### Tier invariant CHECK (the one that bites you most)

Constraint name: `documents_tier_columns_check`. Definition:

```
visibility='common'   AND investor_id IS NULL     AND project_id IS NULL
OR
visibility='project'  AND investor_id IS NULL     AND project_id IS NOT NULL
OR
visibility='investor' AND investor_id IS NOT NULL
```

What this means in practice: you cannot accidentally upload a "project" doc
without picking a project, and you cannot leave a stray `investor_id` on a
common doc. Postgres will reject the INSERT with a check constraint violation.
Project rows must have `investor_id IS NULL` (do not also pin to one investor;
use investor tier for that).

Other CHECKs:

- `documents_visibility_check` — `visibility IN ('common','project','investor')`
- `documents_doc_type_check` — `doc_type IN ('contract','agreement','kyc','other')`

### Indexes

- `idx_documents_visibility (visibility, uploaded_at DESC)`
- `idx_documents_project (project_id, uploaded_at DESC)` (partial, where
  `project_id IS NOT NULL`)

---

## 4. RLS reference

### `public.documents`

Two policies, both for role `authenticated`:

**SELECT — "documents: tiered read"**

```sql
visibility = 'common'
OR (visibility = 'project'
    AND project_id IN (SELECT project_id FROM investor_units
                       WHERE investor_id = (SELECT auth.uid())))
OR (visibility = 'investor'
    AND investor_id = (SELECT auth.uid()))
```

**INSERT — "documents: insert own investor doc"**

```sql
WITH CHECK (
  visibility = 'investor'
  AND investor_id = (SELECT auth.uid())
)
```

Note the absence of UPDATE and DELETE policies — investors cannot mutate
existing rows from the app. All edits and deletes must go through `service_role`
(Studio SQL editor).

### `storage.objects` filtered by `bucket_id='arl-documents'`

Four policies relevant to documents:

| Policy name                                | Role           | Cmd  | Predicate (paraphrased)                                                                 |
|--------------------------------------------|----------------|------|-----------------------------------------------------------------------------------------|
| `investors read common documents`          | authenticated  | SELECT | first folder = `common`                                                               |
| `investors read project documents`         | authenticated  | SELECT | first folder = `project` AND second folder is one of the investor's project_ids        |
| `investors read own investor documents`    | authenticated  | SELECT | first folder = `investor` AND second folder = `auth.uid()`                            |
| `service role full access arl-documents`   | service_role   | ALL    | any object in the bucket                                                              |

There is no investor-facing INSERT/UPDATE/DELETE policy on `storage.objects`
for `arl-documents`. Ops uploads via Studio (service_role) work; the Flutter
app cannot upload directly.

### Bucket properties

- `id` / `name`: `arl-documents`
- `public`: false (downloads always go through signed URLs)
- `file_size_limit`: 52,428,800 bytes (50 MB)
- `allowed_mime_types`: `application/pdf`, `image/jpeg`, `image/png`,
  `image/webp`

If you need to upload anything outside that mime list (a .docx, a .xlsx), the
upload will be rejected by the bucket itself before RLS even runs. Convert to
PDF first.

---

## 5. Flutter UI walkthrough

File: `lib/features/documents/documents_screen.dart`. The screen does no
filtering of its own — it relies entirely on RLS. The repository in
`lib/core/repositories/documents_repository.dart` runs a single query:

```dart
client.from('documents').select().order('uploaded_at', ascending: false)
```

Then it calls `StorageHelper.signedUrlsForBucket('arl-documents', paths)` to
batch-mint 50-minute signed URLs for every row's `storage_path`. Those URLs
are cached in Hive so that an offline reopen still renders the list (the eye
icon may fail to open if the signed URL has expired, but the row stays
visible).

The screen groups rows by `visibility` and emits three accordion sections in
order: Common, My Projects, My Documents. Rows with `visibility` outside the
three valid values fall through to the investor bucket (defensive default).

Tapping the eye icon calls `launchUrl(uri, externalApplication)` against the
signed URL. There is no in-app PDF viewer — the OS / browser handles it.

---

## 6. Live test results (2026-05-15)

Three rows inserted via Studio SQL editor, one per tier, all using the
expected path convention. Then verified visibility from two perspectives:
the test investor (Beta Banana member) and the browser session (a different
investor with units in Xiaomi / Samsung / Pineapple).

### Inserts (all succeeded)

| Visibility | name                              | storage_path                                                                              |
|------------|-----------------------------------|-------------------------------------------------------------------------------------------|
| common     | Test brochure (E2E 2026-05-15)    | `common/test_brochure.txt`                                                                |
| project    | Project test doc 2026-05-15       | `project/9ba53e8f-b508-4123-9c08-335d116c7c6d/test_project_doc.pdf`                       |
| investor   | Investor test doc 2026-05-15      | `investor/27d3735e-470d-47a5-a413-9ae502194d3d/test_kyc_2026_05_15.pdf`                   |

### RLS simulation (`SET LOCAL request.jwt.claims`)

As test investor `27d3735e-...` (Beta Banana member): visible row count = 6
— 2 common, 2 project Beta Banana, 2 investor own. Correct.

As foreign investor `ce23b3bc-...` (UAT End-to-End LLP member, not Beta
Banana): visible row count = 3 — 2 common, 0 project, 1 investor own.
Correct — they cannot see the Beta Banana project doc and cannot see the
test investor's investor-tier doc.

### Flutter UI

Browser session was signed in as `sahil.mohite@agresearchlabs.com` (a
different investor with units in Xiaomi / Samsung / Pineapple, NOT Beta
Banana). Documents screen rendered:

- Common (2 files): ARL Company Profile 2026.pdf, Test brochure (E2E
  2026-05-15) — including correct date `May 15, 2026` and size `1 KB`
- My Projects (0 files): no Beta Banana project doc, as expected
- My Documents (0 files): no Foreign KYC and no Test KYC Acknowledgement,
  because that's a different investor

Conclusion: end-to-end pipeline works for the common tier on a live browser
session. The project and investor tiers were verified via direct RLS
simulation rather than a browser session for the test investor.

### Cleanup

All three test rows were deleted from `public.documents` after verification.
No storage objects were uploaded during the test (the bucket is empty, see
"Defects" below).

---

## 7. Ops recipes

All SQL examples below are meant to be pasted into the Supabase Studio SQL
editor (which runs as `service_role` and bypasses RLS). Storage UI steps
assume Studio → Storage → `arl-documents`.

### D-1: Upload a common document (visible to all investors)

Studio Storage steps:

1. Navigate to Storage → `arl-documents` in Supabase Studio.
2. If no `common/` folder exists, click "Create folder", name it `common`.
3. Open the `common/` folder. Click "Upload file". Pick the PDF (or
   JPEG/PNG/WebP). Wait for the green success toast.
4. Confirm the file appears in the listing.

Then INSERT the catalog row (use the exact filename you uploaded):

```sql
INSERT INTO public.documents
  (visibility, doc_type, name, storage_path, file_size_kb)
VALUES
  ('common', 'other', 'ARL Company Profile 2026',
   'common/arl_profile_2026.pdf', 850);
```

Replace `850` with the actual size in KB if you care about the meta line in
the app (it's cosmetic — NULL is fine).

### D-2: Upload a project-tier document

Find the project_id first:

```sql
SELECT id, name FROM public.projects WHERE name ILIKE '%banana%';
```

Studio Storage:

1. Storage → `arl-documents`. Open `project/` folder (create if missing).
2. Inside, create a folder named exactly with the project's UUID, e.g.
   `9ba53e8f-b508-4123-9c08-335d116c7c6d`.
3. Upload the file into that UUID folder.

Catalog row:

```sql
INSERT INTO public.documents
  (visibility, project_id, doc_type, name, storage_path, file_size_kb)
VALUES
  ('project',
   '9ba53e8f-b508-4123-9c08-335d116c7c6d',
   'agreement',
   'Beta Banana Project Brief 2026',
   'project/9ba53e8f-b508-4123-9c08-335d116c7c6d/brief_2026.pdf',
   1200);
```

The storage path's second segment must be the same UUID as `project_id`.
If they disagree, the row will list but the signed URL will fail when the
investor taps it (and worse, an investor in a different project could see
the row if the project_id matched theirs but the path pointed elsewhere —
keep them aligned).

### D-3: Upload an investor-tier document

Find the investor_id (= their auth user id):

```sql
SELECT id, name, email FROM public.investors WHERE email = 'someone@example.com';
```

Studio Storage:

1. Storage → `arl-documents` → `investor/` folder.
2. Create a subfolder named exactly with the investor's UUID.
3. Upload the file.

Catalog row:

```sql
INSERT INTO public.documents
  (visibility, investor_id, doc_type, name, storage_path, file_size_kb)
VALUES
  ('investor',
   '27d3735e-470d-47a5-a413-9ae502194d3d',
   'kyc',
   'KYC Acknowledgement',
   'investor/27d3735e-470d-47a5-a413-9ae502194d3d/kyc_ack.pdf',
   220);
```

### D-4: Replace a document (same name, new file)

Simplest: overwrite the storage object with a same-named file via Studio
Storage (click the three-dot menu → Replace). The catalog row's
`storage_path` stays the same; the bytes change. The signed URL the app
already cached for that path will keep pointing to the new bytes (the URL
references the path, not a versioned blob ID), so the next app refresh
shows the new content.

If you want to bump `uploaded_at` so the row jumps to the top of the list:

```sql
UPDATE public.documents
SET uploaded_at = now(),
    file_size_kb = 875   -- optional, only if size changed materially
WHERE id = 'the-row-id';
```

If you uploaded under a new filename, also update `storage_path`:

```sql
UPDATE public.documents
SET storage_path = 'common/arl_profile_2026_v2.pdf',
    name = 'ARL Company Profile 2026 (revised)',
    uploaded_at = now()
WHERE id = 'the-row-id';
```

Then delete the old storage object via Studio Storage to free space.

### D-5: Delete a document

Two-step. Don't skip either, or you'll either leak storage or leave broken
links.

1. Delete the catalog row:

```sql
DELETE FROM public.documents WHERE id = 'the-row-id';
```

2. In Studio Storage → `arl-documents`, navigate to the file and delete the
   object. There is no automatic cascade from the table to the bucket.

### D-6: Bulk upload

**One common doc for everyone (single row):** just D-1. There is no per-
investor fan-out — the single common row is visible to every authenticated
investor automatically.

**Per-investor agreement (one row per investor):** loop in SQL. Example:
add a generic NDA reference to every investor who has at least one unit:

```sql
INSERT INTO public.documents
  (visibility, investor_id, doc_type, name, storage_path)
SELECT
  'investor',
  i.id,
  'agreement',
  'Standard NDA 2026-05',
  format('investor/%s/standard_nda_2026_05.pdf', i.id)
FROM public.investors i
WHERE EXISTS (SELECT 1 FROM public.investor_units iu
              WHERE iu.investor_id = i.id)
  AND NOT EXISTS (SELECT 1 FROM public.documents d
                  WHERE d.investor_id = i.id
                    AND d.name = 'Standard NDA 2026-05');
```

That generates the catalog rows. You still have to put the file at every
`investor/<id>/standard_nda_2026_05.pdf` path — either by uploading the
same blob N times via Studio (tedious) or by having engineering write a
one-off Edge Function that copies a single source blob to each target
path. **Until the storage objects exist, the app will list the rows but
the eye icon will fail to open them.**

### D-7: Audit who can see which documents

Count rows per tier:

```sql
SELECT visibility, count(*) FROM public.documents GROUP BY visibility;
```

Find every doc a specific investor can see (substitutes their uid into the
RLS predicate):

```sql
WITH me AS (SELECT '27d3735e-470d-47a5-a413-9ae502194d3d'::uuid AS uid)
SELECT d.id, d.name, d.visibility, d.project_id
FROM public.documents d, me
WHERE
  d.visibility = 'common'
  OR (d.visibility = 'project'
      AND d.project_id IN (SELECT project_id FROM public.investor_units
                           WHERE investor_id = me.uid))
  OR (d.visibility = 'investor'
      AND d.investor_id = me.uid)
ORDER BY d.visibility, d.uploaded_at DESC;
```

Find every investor who can see a given project document (because they hold
units in that project):

```sql
SELECT i.id, i.name, i.email
FROM public.investor_units iu
JOIN public.investors i ON i.id = iu.investor_id
WHERE iu.project_id = '9ba53e8f-b508-4123-9c08-335d116c7c6d';
```

Validate tier invariant integrity (should return zero rows):

```sql
SELECT id, name, visibility, investor_id, project_id
FROM public.documents
WHERE NOT (
  (visibility='common'   AND investor_id IS NULL     AND project_id IS NULL) OR
  (visibility='project'  AND investor_id IS NULL     AND project_id IS NOT NULL) OR
  (visibility='investor' AND investor_id IS NOT NULL)
);
```

The CHECK constraint should prevent these, but verifying periodically is
cheap.

---

## 8. Defects + open questions

### P1 — Existing seed `storage_path` values have a stray `documents/` prefix that the storage RLS does not expect

The four seed rows currently in `public.documents` have paths like
`documents/common/arl_profile.pdf` and
`documents/investor/<uuid>/test_kyc.pdf`. But the storage RLS policies
match on `(storage.foldername(name))[1]`, which is the **first** folder of
the object key.

If an ops engineer uploads the actual file at
`documents/common/arl_profile.pdf` (matching the `storage_path`), then
`foldername[1]` = `'documents'`, which matches none of the three tier
policies, so the file is unreadable by investors (even though the catalog
row lists fine via the DB RLS).

If the file is uploaded at `common/arl_profile.pdf` (matching the RLS
expectation), then the `storage_path` lookup that the Flutter repo does
will return a signed URL for a path that doesn't exist, and the eye icon
will fail.

The migration 033 header comment says `documents/common/<file>`, but the
policy is `(storage.foldername(name))[1] = 'common'`. The comment is
misleading; the policy is authoritative. The seed rows match the comment,
not the policy.

Resolution path (engineering decision):
- Option A: rewrite the four seed `storage_path` values to drop the
  `documents/` prefix, e.g. `common/arl_profile.pdf`. This is what the
  RLS expects. Then upload the actual files under the matching keys.
- Option B: change the storage RLS to look at folder level 2 instead of 1
  (i.e. allow a `documents/` parent folder). This is more invasive and
  the comment header should be the only justification.

The bucket is currently empty (0 objects), so the practical impact is that
the seed rows already render in the app but the eye icon does not work for
any of them. The bug is latent until ops uploads anything. Until decided,
all new uploads must follow the RLS-aligned convention (no `documents/`
prefix), and this doc reflects that.

### P2 — Tests in this audit did NOT actually upload bytes to storage

The three test rows were verified at the catalog (RLS-on-the-table) level
only. The end-to-end "tap the eye icon and the PDF opens" path was not
exercised in this audit because the bucket is empty and Studio uploads via
the SQL MCP are not possible. A second pass should:

1. Upload a 1-page PDF to `arl-documents/common/test.pdf` via the Studio UI.
2. INSERT a row with `storage_path='common/test.pdf'`.
3. Confirm an investor browser session can both see the row and click
   through to the PDF.

### P3 — No UPDATE / DELETE RLS policies on `public.documents`

By design — ops manages mutations through `service_role`. But this means
an investor cannot "delete" their own document (e.g. a KYC packet they want
withdrawn). If self-service deletion is ever a product requirement, a new
policy will be needed. Logged for awareness.

### Open question — soft delete vs hard delete

`public.investors` has a `deleted_at` column (soft delete). `documents`
does not. If an investor is deactivated, their investor-tier docs become
orphaned (RLS predicate fails forever because their `auth.uid()` never
fires again). Ops should explicitly DELETE the catalog rows and the
storage objects as part of investor offboarding (recipe D-5).

---

## 9. Migration references

- `supabase/migrations/20260513020000_032_documents_tiering_schema.sql`
  — adds `visibility`, `project_id`; relaxes `investor_id` NOT NULL;
  installs `documents_tier_columns_check`; adds two new indexes.
- `supabase/migrations/20260513030000_033_documents_tiering_rls.sql`
  — installs `documents: tiered read` SELECT policy and
  `documents: insert own investor doc` INSERT policy on
  `public.documents`; installs three storage SELECT policies on
  `storage.objects` for the `arl-documents` bucket.

Migration 013 (`013_storage_buckets`, not shown here) is the migration
that creates the `arl-documents` bucket and the service_role-full-access
storage policy. If anything is wrong at the bucket level, look there.
