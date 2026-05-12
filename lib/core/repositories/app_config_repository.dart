import 'package:arl_app/core/supabase/supabase_client.dart';

/// Public table — no auth needed. Used for force-update + maintenance.
class AppConfigRepository {
  Future<Map<String, String>> all() async {
    final client = ArlSupabase.client;
    if (client == null) return const {};
    final rows = await client.from('app_config').select('key, value');
    return {
      for (final r in rows)
        (r['key'] ?? '').toString(): (r['value'] ?? '').toString(),
    };
  }
}
