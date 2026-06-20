import 'package:arl_app/core/offline/hive_cache.dart';
import 'package:arl_app/core/offline/resilient_cache.dart';
import 'package:arl_app/core/supabase/supabase_client.dart';
import 'package:arl_app/features/financials/models/payout.dart';
import 'package:arl_app/features/home/models/portfolio_summary.dart';

/// Financials reads. Resilient: cache last successful response, return
/// cached on any failure. Uses unrestricted `.select()` so column drift
/// in the live DB doesn't bubble PostgrestExceptions to the UI.
class FinancialsRepository {
  static const _box = HiveBoxes.financials;
  static const _kSummary = 'portfolio_summary';
  static const _kSummaryNextProject = 'portfolio_summary_next_project';
  static const _kPayouts = 'payouts';
  static const _kPayoutsForPrefix = 'payouts_for_';

  Future<PortfolioSummary?> portfolioSummary({String? investorName}) async {
    final client = ArlSupabase.client;
    if (client == null) return _readSummaryCache(investorName);

    // Wait briefly for the session — same race as myProjects/myAllUnits:
    // on web the JWT is restored from localStorage asynchronously, so a
    // cold-start fetch fires unauthenticated (401), RLS returns nothing,
    // and maybeSingle() returns null → stale Hive cache is served instead.
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (client.auth.currentSession == null &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (client.auth.currentSession == null) return _readSummaryCache(investorName);

    try {
      // Use RPC instead of the view — avoids PostgREST schema-cache
      // issues after DDL changes, and makes auth.uid() filtering explicit
      // inside a SECURITY DEFINER function rather than relying on RLS
      // propagating through the view definition.
      final rpcResult = await client.rpc('get_portfolio_summary');
      final row = (rpcResult is List && (rpcResult as List).isNotEmpty)
          ? (rpcResult as List).first as Map<String, dynamic>?
          : null;
      if (row == null) return _readSummaryCache(investorName);

      String? nextPayoutProjectName;
      try {
        final next = await client
            .from('payouts')
            .select('projects(name)')
            .eq('status', 'pending')
            .order('payout_date', ascending: true)
            .limit(1)
            .maybeSingle();
        if (next != null && next['projects'] is Map) {
          nextPayoutProjectName =
              ((next['projects'] as Map)['name'] ?? '') as String;
        }
      } catch (_) {
        // Ignore — falls back to cached project name (if any).
      }

      final map = Map<String, dynamic>.from(row);
      await ResilientCache.putMap(_box, _kSummary, map);
      if (nextPayoutProjectName != null) {
        await ResilientCache.putMap(
            _box, _kSummaryNextProject, {'name': nextPayoutProjectName});
      }
      return PortfolioSummary.fromSupabase(
        map,
        investorName: investorName ?? '',
        nextPayoutProjectName: nextPayoutProjectName ??
            (ResilientCache.getMap(_box, _kSummaryNextProject)?['name']
                as String?),
      );
    } catch (_) {
      return _readSummaryCache(investorName);
    }
  }

  PortfolioSummary? _readSummaryCache(String? investorName) {
    final cached = ResilientCache.getMap(_box, _kSummary);
    if (cached == null) return null;
    final cachedNext = ResilientCache.getMap(_box, _kSummaryNextProject);
    return PortfolioSummary.fromSupabase(
      cached,
      investorName: investorName ?? '',
      nextPayoutProjectName: cachedNext?['name'] as String?,
    );
  }

  Future<List<Payout>> myPayouts({String? projectId}) async {
    final client = ArlSupabase.client;
    final cacheKey =
        projectId == null ? _kPayouts : '$_kPayoutsForPrefix$projectId';
    if (client == null) return _readPayoutsCache(cacheKey);

    try {
      var query = client.from('payouts').select('*, projects(name)');
      if (projectId != null) {
        query = query.eq('project_id', projectId);
      }
      final rows = await query.order('payout_date', ascending: false);
      final list = (rows as List).cast<Map<String, dynamic>>();
      // Hive can't store nested foreign-table maps cleanly; flatten the
      // project-name into a top-level key before caching.
      final cacheable = list.map((r) {
        final flat = Map<String, dynamic>.from(r);
        if (flat['projects'] is Map) {
          final p = flat['projects'] as Map;
          flat['_project_name'] = p['name'];
          flat.remove('projects');
        }
        return flat;
      }).toList();
      await ResilientCache.putList(_box, cacheKey, cacheable);
      return list
          .map<Payout>((r) => Payout.fromSupabase(Map<String, dynamic>.from(r)))
          .toList();
    } catch (_) {
      return _readPayoutsCache(cacheKey);
    }
  }

  List<Payout> _readPayoutsCache(String cacheKey) {
    final cached = ResilientCache.getList(_box, cacheKey);
    if (cached == null) return const [];
    return cached.map<Payout>((r) {
      final m = Map<String, dynamic>.from(r);
      // Re-hydrate the nested shape Payout.fromSupabase expects.
      if (m.containsKey('_project_name')) {
        m['projects'] = {'name': m.remove('_project_name')};
      }
      return Payout.fromSupabase(m);
    }).toList();
  }
}
