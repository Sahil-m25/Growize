import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arl_app/core/supabase/supabase_client.dart';

/// DPDP data-principal rights: access/export, nomination, and erasure
/// requests. All reads are RLS-scoped to the signed-in user; writes go
/// only to the user's own rows.
class PrivacyRepository {
  /// Assemble a copy of everything we hold about the current user, across
  /// tables. Best-effort per table so one failing query never blocks the
  /// whole export.
  Future<Map<String, dynamic>> exportMyData() async {
    final client = ArlSupabase.client;
    final uid = ArlSupabase.currentUserId;
    final out = <String, dynamic>{
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'user_id': uid,
    };
    if (client == null || uid == null) return out;

    Future<void> grab(String key, Future<dynamic> Function() q) async {
      try {
        out[key] = await q();
      } catch (e) {
        out[key] = {'error': e.toString()};
      }
    }

    await grab('profile', () => client.from('investors').select().eq('id', uid));
    await grab('units',
        () => client.from('investor_units').select().eq('investor_id', uid));
    await grab('payouts',
        () => client.from('payouts').select().eq('investor_id', uid));
    await grab(
        'documents',
        () => client
            .from('documents')
            .select('id,doc_type,name,visibility,uploaded_at')
            .eq('investor_id', uid));
    await grab('notifications',
        () => client.from('notifications').select().eq('investor_id', uid));
    await grab('support_tickets',
        () => client.from('support_tickets').select().eq('investor_id', uid));
    await grab(
        'consents', () => client.from('consents').select().eq('user_id', uid));
    await grab('login_events',
        () => client.from('login_events').select().eq('user_id', uid));
    await grab('consultation_requests',
        () => client.from('consultation_requests').select().eq('user_id', uid));
    await grab('bank_change_requests',
        () => client.from('bank_change_requests').select().eq('investor_id', uid));
    await grab('exit_requests',
        () => client.from('exit_requests').select().eq('investor_id', uid));
    await grab('nominee',
        () => client.from('nominees').select().eq('investor_id', uid));
    await grab(
        'settings',
        () => client
            .from('user_settings')
            .select(
                'biometric_enabled,notifications_enabled,terms_accepted_at,privacy_accepted_at,updated_at')
            .eq('user_id', uid));
    return out;
  }

  String toPrettyJson(Map<String, dynamic> data) =>
      const JsonEncoder.withIndent('  ').convert(data);

  Future<Map<String, dynamic>?> getNominee() async {
    final client = ArlSupabase.client;
    final uid = ArlSupabase.currentUserId;
    if (client == null || uid == null) return null;
    return await client
        .from('nominees')
        .select()
        .eq('investor_id', uid)
        .maybeSingle();
  }

  Future<void> upsertNominee({
    required String name,
    String? relationship,
    String? email,
    String? phone,
  }) async {
    final client = ArlSupabase.requireClient();
    final uid = client.auth.currentUser!.id;
    await client.from('nominees').upsert({
      'investor_id': uid,
      'name': name,
      'relationship': (relationship?.trim().isEmpty ?? true) ? null : relationship!.trim(),
      'email': (email?.trim().isEmpty ?? true) ? null : email!.trim(),
      'phone': (phone?.trim().isEmpty ?? true) ? null : phone!.trim(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'investor_id');
  }

  Future<void> deleteNominee() async {
    final client = ArlSupabase.requireClient();
    final uid = client.auth.currentUser!.id;
    await client.from('nominees').delete().eq('investor_id', uid);
  }

  Future<Map<String, dynamic>?> latestErasureRequest() async {
    final client = ArlSupabase.client;
    final uid = ArlSupabase.currentUserId;
    if (client == null || uid == null) return null;
    return await client
        .from('erasure_requests')
        .select()
        .eq('investor_id', uid)
        .order('requested_at', ascending: false)
        .limit(1)
        .maybeSingle();
  }

  Future<void> requestErasure({String? reason}) async {
    final client = ArlSupabase.requireClient();
    final uid = client.auth.currentUser!.id;
    await client.from('erasure_requests').insert({
      'investor_id': uid,
      'reason': (reason?.trim().isEmpty ?? true) ? null : reason!.trim(),
    });
  }
}

final privacyRepositoryProvider =
    Provider<PrivacyRepository>((ref) => PrivacyRepository());
