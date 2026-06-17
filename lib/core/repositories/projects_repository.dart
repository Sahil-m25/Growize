import 'package:arl_app/core/offline/hive_cache.dart';
import 'package:arl_app/core/offline/resilient_cache.dart';
import 'package:arl_app/core/supabase/supabase_client.dart';
import 'package:arl_app/features/projects/models/marketplace_project.dart';
import 'package:arl_app/features/projects/models/project.dart';
import 'package:arl_app/features/projects/models/project_phase.dart';
import 'package:arl_app/features/projects/models/project_update.dart';

/// All project queries.
///
/// Resilience model:
///   - Each method wraps the live fetch in try/catch.
///   - On success → cache rows to Hive + return.
///   - On failure (network drop, 42703 column missing, RLS denial, …)
///     → return last cached rows (or empty list) so the UI never crashes.
///   - We `.select()` without an explicit column list to survive schema
///     drift between the app + a freshly-applied DB. Models already cope
///     with missing keys via null-coalescing in `fromSupabase`.
class ProjectsRepository {
  static const _box = HiveBoxes.projects;
  // v2 — old `my_projects` key was poisoned by an empty-list write that
  // ran before the JWT was attached on web. Bumping the key lets every
  // existing client re-fetch from the network on next launch.
  static const _kMyProjects = 'my_projects_v3'; // v3: forces re-fetch after progressPercent fix
  static const _kMarketplace = 'marketplace';
  static const _kProjectById = 'project_by_id_';
  static const _kPhases = 'phases_';
  static const _kUpdates = 'updates_';
  static const _kAllocation = 'allocation_';
  static const _kAllUnits = 'all_units';

  /// Returns ONLY projects the investor has units in.
  ///
  /// Filters via RLS (`investor_units.investor_id = auth.uid()`) rather
  /// than a Dart-side `.eq('investor_id', uid)` so the query is driven
  /// by the JWT in the request. Avoids the race where this method runs
  /// before `client.auth.currentUser` is populated by Supabase.
  Future<List<Project>> myProjects() async {
    final client = ArlSupabase.client;
    if (client == null) return _readMyProjectsCache();

    // Wait briefly for the session if it isn't ready yet — covers the
    // race where projectsProvider runs before Supabase finishes
    // restoring the session from localStorage.
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (client.auth.currentSession == null &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (client.auth.currentSession == null) return _readMyProjectsCache();

    try {
      // RLS filters investor_units to rows where investor_id = auth.uid().
      // Also exclude soft-deleted rows so a stale duplicate doesn't surface
      // a project the investor no longer has an active allocation in.
      final unitsRows = await client
          .from('investor_units')
          .select('project_id')
          .isFilter('deleted_at', null);
      final ids = unitsRows
          .map<String>((r) => (r['project_id'] ?? '') as String)
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList();
      if (ids.isEmpty) {
        // Don't cache an empty result — this branch fires both when the
        // investor genuinely has no allocations AND when the JWT wasn't
        // attached yet (RLS-denied 0 rows). Caching `[]` here used to
        // poison Hive across cold restarts; now we let the next call
        // re-query the network.
        return const [];
      }

      final rows = await client
          .from('projects')
          .select()
          .inFilter('id', ids)
          .isFilter('deleted_at', null);
      final list = (rows as List).cast<Map<String, dynamic>>();
      await ResilientCache.putList(_box, _kMyProjects, list);
      return list.map<Project>((r) => Project.fromSupabase(r)).toList();
    } catch (_) {
      return _readMyProjectsCache();
    }
  }

  List<Project> _readMyProjectsCache() {
    final cached = ResilientCache.getList(_box, _kMyProjects);
    if (cached == null) return const [];
    return cached.map<Project>((r) => Project.fromSupabase(r)).toList();
  }

  /// Marketplace listings. We try the indexed-flag filter first; if the
  /// column doesn't exist on this environment we fall back to fetching
  /// every visible project and let the UI filter via [MarketplaceProject]
  /// invariants.
  Future<List<MarketplaceProject>> marketplaceProjects() async {
    final client = ArlSupabase.client;
    if (client == null) return _readMarketplaceCache();

    try {
      List<dynamic> rows;
      try {
        rows = await client
            .from('projects')
            .select()
            .eq('is_listed_in_marketplace', true)
            .isFilter('deleted_at', null)
            .order('marketplace_sort_order', ascending: true);
      } catch (_) {
        // Schema drift: marketplace columns missing. Fetch all + skip
        // sort so the user still sees listings.
        rows =
            await client.from('projects').select().isFilter('deleted_at', null);
      }
      final list = rows.cast<Map<String, dynamic>>();
      await ResilientCache.putList(_box, _kMarketplace, list);
      return list
          .map<MarketplaceProject>((r) => MarketplaceProject.fromSupabase(r))
          .toList();
    } catch (_) {
      return _readMarketplaceCache();
    }
  }

  List<MarketplaceProject> _readMarketplaceCache() {
    final cached = ResilientCache.getList(_box, _kMarketplace);
    if (cached == null) return const [];
    return cached
        .map<MarketplaceProject>((r) => MarketplaceProject.fromSupabase(r))
        .toList();
  }

  Future<Project?> projectById(String id) async {
    final client = ArlSupabase.client;
    if (client == null) return _readProjectByIdCache(id);

    try {
      final row = await client
          .from('projects')
          .select()
          .eq('id', id)
          .isFilter('deleted_at', null)
          .maybeSingle();
      if (row == null) return _readProjectByIdCache(id);
      await ResilientCache.putMap(
          _box, '$_kProjectById$id', Map<String, dynamic>.from(row));
      return Project.fromSupabase(Map<String, dynamic>.from(row));
    } catch (_) {
      return _readProjectByIdCache(id);
    }
  }

  Project? _readProjectByIdCache(String id) {
    final cached = ResilientCache.getMap(_box, '$_kProjectById$id');
    if (cached == null) return null;
    return Project.fromSupabase(cached);
  }

  Future<Map<String, dynamic>?> myUnitsForProject(String projectId) async {
    // Demo project IDs (`demo:xxx`) are not valid UUIDs — querying
    // PostgREST with one yields a 400 "invalid input syntax for uuid".
    // Skip the network round-trip entirely.
    if (projectId.isEmpty || projectId.startsWith('demo:')) return null;

    final client = ArlSupabase.client;
    if (client == null) return _readAllocationCache(projectId);

    // Wait briefly for the session if it isn't ready yet — same race
    // as currentInvestor / myProjects.
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (client.auth.currentSession == null &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (client.auth.currentSession == null) {
      return _readAllocationCache(projectId);
    }

    try {
      // RLS filters investor_units by investor_id = auth.uid().
      // Filter soft-deleted rows and order by most recently updated so that
      // if duplicate active rows ever exist, the freshest one wins.
      final row = await client
          .from('investor_units')
          .select()
          .eq('project_id', projectId)
          .isFilter('deleted_at', null)
          .order('updated_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (row == null) return null;
      final map = Map<String, dynamic>.from(row);
      await ResilientCache.putMap(_box, '$_kAllocation$projectId', map);
      return map;
    } catch (_) {
      return _readAllocationCache(projectId);
    }
  }

  Map<String, dynamic>? _readAllocationCache(String projectId) {
    return ResilientCache.getMap(_box, '$_kAllocation$projectId');
  }

  /// All `investor_units` rows for the signed-in investor in one query.
  /// Powers the projects-list cards: a single bulk fetch is both faster
  /// than N concurrent per-project queries AND avoids the silent-null
  /// failure mode `.maybeSingle()` exhibits when called concurrently
  /// for sibling cards on cold mount.
  Future<List<Map<String, dynamic>>> myAllUnits() async {
    final client = ArlSupabase.client;
    if (client == null) return _readAllUnitsCache();

    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (client.auth.currentSession == null &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (client.auth.currentSession == null) return _readAllUnitsCache();

    try {
      // RLS filters by investor_id = auth.uid(); filter soft-deleted rows.
      final rows = await client
          .from('investor_units')
          .select()
          .isFilter('deleted_at', null);
      final list = (rows as List).cast<Map<String, dynamic>>();
      await ResilientCache.putList(_box, _kAllUnits, list);
      return list;
    } catch (_) {
      return _readAllUnitsCache();
    }
  }

  List<Map<String, dynamic>> _readAllUnitsCache() {
    final cached = ResilientCache.getList(_box, _kAllUnits);
    if (cached == null) return const [];
    return cached.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  Future<List<ProjectPhase>> phasesFor(String projectId) async {
    final client = ArlSupabase.client;
    if (client == null) return _readPhasesCache(projectId);
    try {
      final rows = await client
          .from('project_phases')
          .select()
          .eq('project_id', projectId)
          .order('sort_order', ascending: true);
      final list = (rows as List).cast<Map<String, dynamic>>();
      await ResilientCache.putList(_box, '$_kPhases$projectId', list);
      return list.map<ProjectPhase>((r) => ProjectPhase.fromJson(r)).toList();
    } catch (_) {
      return _readPhasesCache(projectId);
    }
  }

  List<ProjectPhase> _readPhasesCache(String projectId) {
    final cached = ResilientCache.getList(_box, '$_kPhases$projectId');
    if (cached == null) return const [];
    return cached.map<ProjectPhase>((r) => ProjectPhase.fromJson(r)).toList();
  }

  /// Monthly project updates (narrative posts), most-recent-first.
  /// Limited to 6 rows — the UI surfaces a single card per update and
  /// older entries roll off rather than paginate.
  Future<List<ProjectUpdate>> updatesFor(String projectId) async {
    if (projectId.isEmpty || projectId.startsWith('demo:')) return const [];

    final client = ArlSupabase.client;
    if (client == null) return _readUpdatesCache(projectId);
    try {
      final rows = await client
          .from('project_updates')
          .select()
          .eq('project_id', projectId)
          .order('update_date', ascending: false)
          .limit(6);
      final list = (rows as List).cast<Map<String, dynamic>>();
      await ResilientCache.putList(_box, '$_kUpdates$projectId', list);
      return list
          .map<ProjectUpdate>((r) => ProjectUpdate.fromJson(r))
          .toList();
    } catch (_) {
      return _readUpdatesCache(projectId);
    }
  }

  List<ProjectUpdate> _readUpdatesCache(String projectId) {
    final cached = ResilientCache.getList(_box, '$_kUpdates$projectId');
    if (cached == null) return const [];
    return cached
        .map<ProjectUpdate>((r) => ProjectUpdate.fromJson(r))
        .toList();
  }
}
