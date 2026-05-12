# Workflow Audit — 2026-04-27

Assessment of `~/.claude/CLAUDE.md` + `~/.claude/WORKFLOW.md` + `~/.claude/settings.json` + project `.claude/`.

## Verdict
**Mid.** Strong scaffolding, weak enforcement, lots of bloat. ~40% optimized. Wins on token efficiency (caveman + context-mode). Loses on skill sprawl, missing project logs, no hook-level guardrails.

---

## Strong (keep)
1. **context-mode hooks active** — PreToolUse blocks Bash/WebFetch flooding. Real win.
2. **caveman plugin** — token savings on output.
3. **Phase gates documented** in CLAUDE.md (Ideate→Plan→Implement→Verify→Ship).
4. **claude-mem cross-session search** wired.
5. **WORKFLOW.md reference** — clean, scannable.
6. **`skipDangerousModePermissionPrompt: true`** + narrow ctx allowlist — fewer prompts.

---

## Problems

### 1. Skill sprawl (49 skills enabled)
gstack suite alone = 19 skills. Most never used solo dev Flutter project. Cost: longer skill descriptions in every prompt = wasted tokens every turn.
**Fix:** disable gstack-* unless using gstack pipeline. Disable nextjs-performance (Flutter project). Disable gtm-metrics, biz-toc, business-model-auditor, competitive-analysis, notion-research-documentation if not active. Move to `skills_disabled/`.

### 2. Project `.claude/` not scaffolded
Current arl_app `.claude/`:
```
INVESTIGATION_REPORT.md
settings.local.json
```
Missing per CLAUDE.md §6: `INDEX.md`, `status.md`, `scope.md`, `decisions/`, `iterations/`.
**Fix:** run `bash ~/.claude/scripts/init-project-logs.sh` in project root. Without these, "phase gates" + "log system" rules in CLAUDE.md are dead letters.

### 3. No CLAUDE.md in project
Global CLAUDE.md ≠ project context. arl_app has no `CLAUDE.md` at root. Each session relearns Flutter+Growize parity work from memory dump.
**Fix:** write `arl_app/CLAUDE.md` w/ design source-of-truth (`Growize App Design.html`), key files, color tokens, current state. Reference INVESTIGATION_REPORT findings.

### 4. MCP config empty but skills reference servers
`~/.claude/mcp.json = {"mcpServers": {}}`. WORKFLOW.md lists Notion/Zoho/Supabase/etc. Yet Supabase + Zoho + NotebookLM tools exposed via deferred ToolSearch — so configured elsewhere (project-level or remote-settings).
**Fix:** consolidate to one location. Audit which MCPs actually used. Supabase + claude-mem + context-mode likely enough.

### 5. No quality hooks
Only context-mode hooks present. No:
- `PostToolUse` lint/format on Edit
- `Stop` hook checking unfinished todos
- `UserPromptSubmit` injecting project state
**Fix:** add Flutter `dart format` + `flutter analyze` PostToolUse on `*.dart` Edits.

### 6. Permission allowlist too narrow
Only 4 ctx_* tools allowed. Every git/dart/flutter command prompts.
**Fix:** invoke `/fewer-permission-prompts` skill — auto-allowlist common reads.

### 7. Phase gates not enforced
CLAUDE.md says "every task flows through phases" but nothing blocks skipping. Ideate→Plan→Implement→Verify happens by discipline only.
**Fix:** UserPromptSubmit hook detect "fix bug" / "add feature" → inject reminder. Or accept that gates are guidance, drop the table.

### 8. Caveman conflicts w/ verbose skills
gstack-* skills produce structured long output. Caveman cuts fluff. Either or — currently both running.

### 9. Memory bloat
auto-memory `MEMORY.md` truncates after 200 lines. With 49 skills + multi-session activity, index overflows fast.
**Fix:** invoke `anthropic-skills:consolidate-memory` periodically. Prune.

### 10. `INVESTIGATION_REPORT.md` not indexed
Lives at `.claude/` root, not `decisions/`. Won't be retrieved by `ctx_search` patterns documented in WORKFLOW.md.
**Fix:** move to `.claude/decisions/2026-04-24_html-parity-gap.md`.

---

## Priority Fix Order
1. `bash ~/.claude/scripts/init-project-logs.sh` in arl_app
2. Write `arl_app/CLAUDE.md`
3. Disable unused skills (gstack, nextjs-perf, biz suite) → `skills_disabled/`
4. Move INVESTIGATION_REPORT → decisions/
5. Run `/fewer-permission-prompts`
6. Add Flutter format/analyze PostToolUse hook
7. Consolidate MCP config to one file
8. Choose: caveman OR gstack verbose, not both

---

## Token Cost Estimate
Current setup: ~8-12K tokens/session loaded just from skill descriptions + CLAUDE.md + WORKFLOW.md + memory index.
After fixes: ~3-5K. **~60% reduction** before any real work.
