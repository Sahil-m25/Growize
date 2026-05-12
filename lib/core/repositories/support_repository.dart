import 'package:arl_app/core/constants/supabase_constants.dart';
import 'package:arl_app/core/supabase/supabase_client.dart';

/// Support tickets, ticket messages, and bank change requests.
/// Writes go through Edge Functions (rate-limiting, email notifications).
class SupportRepository {
  Future<List<Map<String, dynamic>>> myTickets() async {
    final client = ArlSupabase.client;
    if (client == null) return const [];
    final rows = await client
        .from('support_tickets')
        .select('id, investor_id, project_id, category, subject, status, '
            'created_at, updated_at')
        .order('updated_at', ascending: false);
    return rows.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>?> ticketById(String id) async {
    final client = ArlSupabase.client;
    if (client == null) return null;
    return await client
        .from('support_tickets')
        .select('id, investor_id, project_id, category, subject, status, '
            'created_at, updated_at')
        .eq('id', id)
        .maybeSingle();
  }

  Future<List<Map<String, dynamic>>> messagesFor(String ticketId) async {
    final client = ArlSupabase.client;
    if (client == null) return const [];
    final rows = await client
        .from('ticket_messages')
        .select('id, ticket_id, sender_type, body, created_at')
        .eq('ticket_id', ticketId)
        .order('created_at', ascending: true);
    return rows.cast<Map<String, dynamic>>();
  }

  /// Calls create-ticket Edge Function (rate-limit + email + multi-row insert).
  Future<String> createTicket({
    required String category,
    required String subject,
    required String body,
    String? projectId,
  }) async {
    final client = ArlSupabase.requireClient();
    final res = await client.functions.invoke(
      SupabaseConstants.fnCreateTicket,
      body: {
        'category': category,
        'subject': subject,
        'body': body,
        if (projectId != null) 'project_id': projectId,
      },
    );
    final data = res.data as Map<String, dynamic>?;
    return data?['ticket_id'] as String? ?? '';
  }

  Future<void> replyTicket({
    required String ticketId,
    required String body,
  }) async {
    final client = ArlSupabase.requireClient();
    await client.functions.invoke(
      SupabaseConstants.fnReplyTicket,
      body: {'ticket_id': ticketId, 'body': body},
    );
  }

  Future<List<Map<String, dynamic>>> myBankChangeRequests() async {
    final client = ArlSupabase.client;
    if (client == null) return const [];
    final rows = await client
        .from('bank_change_requests')
        .select('id, investor_id, new_bank_name, new_account_masked, '
            'new_ifsc, new_holder_name, status, notes, '
            'requested_at, resolved_at')
        .order('requested_at', ascending: false);
    return rows.cast<Map<String, dynamic>>();
  }

  Future<void> requestBankChange({
    required String bankName,
    required String accountMasked,
    required String ifsc,
    required String holderName,
  }) async {
    final client = ArlSupabase.requireClient();
    await client.functions.invoke(
      SupabaseConstants.fnBankChangeRequest,
      body: {
        'bank_name': bankName,
        'account_masked': accountMasked,
        'ifsc': ifsc,
        'holder_name': holderName,
      },
    );
  }
}
