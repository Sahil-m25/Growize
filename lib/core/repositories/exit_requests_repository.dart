import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:arl_app/core/supabase/supabase_client.dart';

/// Persists investor exit requests against a specific `investor_units`
/// row. RLS scopes reads/writes to the authenticated user; ARL staff
/// work the queue via service_role (Studio / future Edge Function).
///
/// Duplicate guard: the DB has a partial unique index on
/// (investor_unit_id) WHERE status='pending'. We catch the
/// PostgrestException with code 23505 and surface the existing
/// pending row instead of failing — race-safe and "already submitted"
/// is a friendlier UX than "unique violation".
class ExitRequestsRepository {
  Future<ExitRequestCreateResult> createExit({
    required String investorUnitId,
    String? reason,
  }) async {
    final client = ArlSupabase.requireClient();
    final uid = client.auth.currentUser!.id;
    try {
      final inserted = await client
          .from('exit_requests')
          .insert({
            'investor_unit_id': investorUnitId,
            'user_id': uid,
            if (reason != null && reason.isNotEmpty) 'reason': reason,
          })
          .select()
          .single();
      return ExitRequestCreateResult(
        created: true,
        row: Map<String, dynamic>.from(inserted),
      );
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        final existing = await myPendingForUnit(investorUnitId);
        return ExitRequestCreateResult(
          created: false,
          row: existing ?? const <String, dynamic>{},
        );
      }
      rethrow;
    }
  }

  /// Most recent pending request for this user + unit, or null. Drives
  /// the screen's "Exit request submitted" state and disables the CTA
  /// once a request exists.
  Future<Map<String, dynamic>?> myPendingForUnit(String investorUnitId) async {
    final client = ArlSupabase.client;
    final uid = ArlSupabase.currentUserId;
    if (client == null || uid == null) return null;
    final row = await client
        .from('exit_requests')
        .select('id, investor_unit_id, reason, status, created_at')
        .eq('user_id', uid)
        .eq('investor_unit_id', investorUnitId)
        .eq('status', 'pending')
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return row == null ? null : Map<String, dynamic>.from(row);
  }
}

class ExitRequestCreateResult {
  final bool created;
  final Map<String, dynamic> row;
  const ExitRequestCreateResult({required this.created, required this.row});
}
