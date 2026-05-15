# 2026-05-15 — documents.storage_path drops the legacy 'documents/' prefix

**Status:** Implemented in migration 047.

## Context

`DEF-2026-05-15-02` / `DOC-RLS-PATH`. Storage RLS for the
`arl-documents` bucket reads `(storage.foldername(name))[1]` and
matches against `'common' | 'project' | 'investor'`. The four seed
rows in `public.documents` (and Migration 033's misleading header
comment) used paths like `documents/common/<file>`. The moment ops
uploads any bytes, the catalogue + the storage RLS would disagree:

- If they upload to `documents/common/<file>` (matching the catalogue),
  the RLS predicate matches `'documents'` which is not a tier folder
  → file unreadable.
- If they upload to `common/<file>` (matching the RLS), the catalogue
  signed-URL lookup points at a non-existent key → eye icon fails.

The bucket is empty today; the bug is latent until first upload.

## Decision (Option A)

Strip the `documents/` prefix from the four catalogue rows and add a
CHECK constraint preventing future inserts with that prefix. Bucket
structure stays flat: `common/<file>`, `project/<uuid>/<file>`,
`investor/<uuid>/<file>`.

## Why Option A over Option B (widen RLS to folder level 2)

- Migration 033's comment was the only doc claiming folder-level-2
  paths; the policy code disagreed. Cheaper to align catalogue + ops
  flow with the policy than to rewrite the policy.
- A widened RLS would split the bucket prefix from the tier folder,
  inflating object keys and adding a parsing step on every signed URL.
- The CHECK constraint guarantees the drift cannot reappear silently
  in a future Studio-driven INSERT.

## Trade-offs

- Pro: storage RLS, catalogue, and ops upload procedure agree.
- Pro: CHECK forecloses regression.
- Con: any ops procedure docs still referencing the old `documents/`
  prefix need a one-line edit. `docs/ops/documents.md` already noted
  this resolution path as Option A.
