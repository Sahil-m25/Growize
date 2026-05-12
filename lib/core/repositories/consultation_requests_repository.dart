import 'package:arl_app/core/supabase/supabase_client.dart';

/// Persists marketplace consultation requests written from the Explore
/// screen "Request Consultation" CTA. RLS scopes reads/writes to the
/// authenticated user; ARL staff work the queue via service_role.
class ConsultationRequestsRepository {
  static const Duration _dedupWindow = Duration(hours: 24);

  /// Result of [createConsultation]. `created` is false when a recent
  /// "new" request from this user for this project already exists —
  /// the caller can show a friendlier toast in that case.
  Future<ConsultationCreateResult> createConsultation({
    required String projectId,
    required int unitsRequested,
    String? message,
  }) async {
    final client = ArlSupabase.requireClient();
    final uid = client.auth.currentUser!.id;

    final cutoff = DateTime.now()
        .toUtc()
        .subtract(_dedupWindow)
        .toIso8601String();

    final existing = await client
        .from('consultation_requests')
        .select('id, status, created_at')
        .eq('user_id', uid)
        .eq('project_id', projectId)
        .eq('status', 'new')
        .gte('created_at', cutoff)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (existing != null) {
      return ConsultationCreateResult(
        created: false,
        row: Map<String, dynamic>.from(existing),
      );
    }

    final inserted = await client
        .from('consultation_requests')
        .insert({
          'user_id': uid,
          'project_id': projectId,
          'units_requested': unitsRequested,
          if (message != null && message.isNotEmpty) 'message': message,
        })
        .select()
        .single();
    return ConsultationCreateResult(
      created: true,
      row: Map<String, dynamic>.from(inserted),
    );
  }
}

class ConsultationCreateResult {
  final bool created;
  final Map<String, dynamic> row;
  const ConsultationCreateResult({required this.created, required this.row});
}
