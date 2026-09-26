import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arl_app/core/auth/session_manager.dart';
import 'package:arl_app/core/connectivity/sync_state.dart';
import 'package:arl_app/core/mock/demo_data.dart';
import 'package:arl_app/core/providers/repositories.dart';
import 'package:arl_app/features/auth/auth_provider.dart';
import 'package:arl_app/features/projects/models/investor_unit.dart';
import 'package:arl_app/features/projects/models/marketplace_project.dart';
import 'package:arl_app/features/projects/models/project.dart';
import 'package:arl_app/features/projects/models/project_phase.dart';
import 'package:arl_app/features/projects/models/project_update.dart';
// Imported transitively via repositories.dart (currentInvestorProvider).

/// Currently selected project (null = "all"). Drives the home/financials
/// scoping. Lives at the project level so the bottom-nav + selector share it.
final selectedProjectIdProvider = StateProvider<String?>((ref) => null);

final selectedProjectProvider = Provider<Project?>((ref) {
  final selectedId = ref.watch(selectedProjectIdProvider);
  if (selectedId == null) return null;
  final projects = ref.watch(projectsProvider).valueOrNull ?? const [];
  for (final p in projects) {
    if (p.id == selectedId) return p;
  }
  return null;
});

/// B.T6: Projects list.
/// When an investor row exists for the signed-in user we always return their
/// real projects — possibly an empty list if Zoho hasn't synced allocations yet
/// (show "No projects yet"). Demo projects are reserved for the
/// unauthenticated design-preview flow.
final projectsProvider = FutureProvider<List<Project>>((ref) async {
  // Rebuild on auth state changes so a successful sign-in picks up
  // the real investor row instead of staying on the cached demo list.
  ref.watch(authStateProvider);

  final repo = ref.watch(projectsRepositoryProvider);

  Future<List<Project>> fetchReal() async {
    try {
      final projects = await trackedFetch(ref, () => repo.myProjects());
      if (projects.isEmpty) return const <Project>[];

      // `Project.fromSupabase` already derives `progressPercent` from the
      // elapsed-vs-total months of the contract. That is exactly what the
      // home "Contract Progress" card represents — the percentage, the
      // gradient bar fill, and the "Month X of Y" label all read off the
      // same month-based value, so they stay in sync. The design spec ties
      // the percentage to the contract timeline too (e.g. Month 9 of 60 =>
      // 15%, Month 27 of 60 => 45%).
      //
      // We deliberately do NOT overwrite `progressPercent` with a
      // phase-completion ratio here. Doing so (a) decoupled the bar/percent
      // from the "Month X of Y" label and (b) forced 0% for every project
      // that has no `project_phases` rows yet — which is why the bar showed
      // empty while the label still read e.g. "Month 9 of 60".
      // Personalise the term: each investor's timeline runs from the day
      // they paid in full, so "Month X of 60", the bar and start/end
      // dates differ per investor. Unit fetch failure → farm timeline.
      List<InvestorUnit> units = const [];
      try {
        final rows = await repo.myAllUnits();
        units = rows.map(InvestorUnit.fromJson).toList();
      } catch (_) {}
      return projects.map((p) => personaliseTerm(p, units)).toList();
    } catch (_) {
      // Timeout / network hang on the project list itself → empty
      // (header still renders).
      return const <Project>[];
    }
  }

  // If the user is signed in we never show demo data — even if the
  // investor row hasn't resolved yet (race) or returned null. Demo
  // rows are reserved strictly for unauthenticated design preview.
  if (SessionManager.isLoggedIn) {
    return fetchReal();
  }

  try {
    final investor = await ref.watch(currentInvestorProvider.future);
    if (investor != null) {
      return fetchReal();
    }
  } catch (_) {
    // Auth chain failed — fall through to demo browsing.
  }
  return demoProjects();
});

final projectByIdProvider =
    FutureProvider.family<Project?, String>((ref, id) async {
  // For demo IDs we already have the data in the projects list.
  final list = await ref.watch(projectsProvider.future);
  for (final p in list) {
    if (p.id == id) return p;
  }
  // Real ID not in list (rare race) — query directly.
  if (!id.startsWith(demoIdPrefix)) {
    try {
      return ref.read(projectsRepositoryProvider).projectById(id);
    } catch (_) {
      // Let the detail screen render its "Project not found / couldn't
      // load" state rather than surfacing a raw error.
      return null;
    }
  }
  return null;
});

/// Phases for a given project. Mirrors projects: real first, demo fallback.
final projectPhasesProvider =
    FutureProvider.family<List<ProjectPhase>, String>((ref, projectId) async {
  if (projectId.startsWith(demoIdPrefix)) return demoPhases(projectId);
  final repo = ref.watch(projectsRepositoryProvider);
  final phases = await repo.phasesFor(projectId);
  if (phases.isNotEmpty) return phases;
  return demoPhases(projectId);
});

/// Monthly Updates for a project — narrative posts surfaced on the
/// Project Detail screen. Real Supabase rows only; demo projects return
/// an empty list (the empty-state copy renders for those).
final projectUpdatesProvider =
    FutureProvider.family<List<ProjectUpdate>, String>((ref, projectId) async {
  ref.watch(authStateProvider);
  if (projectId.startsWith(demoIdPrefix)) return const <ProjectUpdate>[];
  final repo = ref.watch(projectsRepositoryProvider);
  try {
    return await repo.updatesFor(projectId);
  } catch (_) {
    return const <ProjectUpdate>[];
  }
});

/// Per-project allocation for the signed-in investor. Returns null when
/// the investor has no units in that project (e.g. they're viewing a
/// marketplace listing they haven't subscribed to yet).
///
/// Watches authStateProvider so the result re-fetches the moment a
/// session attaches. Without this, a card whose Consumer fires before
/// the JWT lands resolves to null, gets cached, and the list shows "—"
/// for every project even after the detail page resolves correctly.
final investorAllocationProvider =
    FutureProvider.family<InvestorUnit?, String>((ref, projectId) async {
  ref.watch(authStateProvider);
  final repo = ref.watch(projectsRepositoryProvider);
  try {
    final row = await repo.myUnitsForProject(projectId);
    if (row == null) return null;
    return InvestorUnit.fromJson(row);
  } catch (_) {
    // Network/RLS hiccup — resolve to "no allocation" rather than leaving
    // the consuming card stuck on a skeleton forever.
    return null;
  }
});

/// All `investor_units` rows for the signed-in investor.
///
/// Used by the projects-list cards instead of N parallel
/// `investorAllocationProvider(id)` calls. The single bulk query is
/// faster, races less, and sidesteps a `.maybeSingle()` quirk we saw
/// where a concurrent batch of single-row queries silently resolved
/// to null even though the rows existed under RLS.
final investorUnitsListProvider =
    FutureProvider<List<InvestorUnit>>((ref) async {
  ref.watch(authStateProvider);
  final repo = ref.watch(projectsRepositoryProvider);
  try {
    final rows = await repo.myAllUnits();
    return rows.map(InvestorUnit.fromJson).toList();
  } catch (_) {
    // Resolve to empty so list/detail cards fall back to their empty
    // state instead of an endless skeleton on a transient failure.
    return const <InvestorUnit>[];
  }
});

/// Marketplace listings shown on the Explore tab. Driven by the
/// `is_listed_in_marketplace` flag on `public.projects` — admins manage
/// the list directly in Supabase Studio.
final marketplaceProjectsProvider =
    FutureProvider<List<MarketplaceProject>>((ref) async {
  final repo = ref.watch(projectsRepositoryProvider);
  try {
    return await trackedFetch(ref, () => repo.marketplaceProjects());
  } catch (_) {
    return const <MarketplaceProject>[];
  }
});


/// Rewrites a project's timeline to the signed-in investor's own term.
///
/// * Paid in full (nothing outstanding): term starts on the earliest
///   `investment_date` of their allotments in this project and runs
///   `totalMonths`. Month counter, bar and start/end follow that.
/// * Money still due: term not started — month 0, empty bar, and
///   [Project.amountToComplete] carries what is left, for a gentle nudge.
///
/// Projects the investor holds no units in are returned unchanged.
Project personaliseTerm(Project p, List<InvestorUnit> allUnits) {
  final units = allUnits.where((u) => u.projectId == p.id && !u.isDemo);
  if (units.isEmpty) return p;

  double due = 0;
  DateTime? start;
  for (final u in units) {
    var left = u.capitalOutstanding > u.totalAmountReceivable
        ? u.capitalOutstanding
        : u.totalAmountReceivable;
    // Some rows carry only invested vs received. Treat a row with no
    // payment figures at all as settled, so missing data never nags.
    if (left <= 0 &&
        u.totalAmountReceived > 0 &&
        u.capitalInvested > u.totalAmountReceived) {
      left = u.capitalInvested - u.totalAmountReceived;
    }
    due += left > 0 ? left : 0;
    final d = u.investmentDate;
    if (d != null && (start == null || d.isBefore(start))) start = d;
  }

  if (due > 0) {
    return p.copyWith(
      termStarted: false,
      amountToComplete: due,
      monthOfContract: 0,
      progressPercent: 0,
    );
  }
  if (start == null) return p;

  final total = p.totalMonths > 0 ? p.totalMonths : 60;
  final end = DateTime(start.year, start.month + total, start.day);
  final now = DateTime.now();
  var elapsed = (now.year - start.year) * 12 + (now.month - start.month);
  if (now.day < start.day) elapsed -= 1;
  elapsed = elapsed.clamp(0, total);
  return p.copyWith(
    startDate: start,
    endDate: end,
    monthOfContract: elapsed < total ? elapsed + 1 : total,
    progressPercent: elapsed / total * 100,
    termStarted: true,
    amountToComplete: 0,
  );
}
