# Project Scope — arl_app

**Last updated:** 2026-04-27

## Active (In Scope)
- [ ] Add `assets:` + `fonts:` sections to pubspec.yaml (Inter family, Logo (4).png → assets/)
- [ ] Global sticky header widget (logo left, bell+avatar right) on every page
- [ ] Back-nav stack preservation (push vs go decisions per route)
- [ ] Project-selector dropdown in global header (not Home-only)
- [ ] Notification dot on bell icon (live count)
- [ ] Activity screen: notifications↔timeline toggle

## Completed
- Riverpod + GoRouter + Supabase wiring
- 17-page screen scaffolding across features/
- Risk/Return 4-quadrant chart, gallery date grouping, 5yr projection bars, profile tiles, exit dialog, project-detail phases, financials tabs

## Dead Ends
<!-- Things definitively ruled out — agent should never re-attempt these -->

## Open Questions
- Should back nav use `pop()` (stack-aware) or `go()` (declarative replace)? Current mix is inconsistent.
- Notification source — Supabase realtime or polling?

## Out of Scope
- Server-side changes (Supabase schema is frozen for parity work)
- Native iOS/Android-specific features beyond local_auth
