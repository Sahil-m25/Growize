import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:arl_app/core/navigation/route_names.dart';
import 'package:arl_app/core/providers/repositories.dart';
import 'package:arl_app/core/supabase/supabase_client.dart';
import 'package:arl_app/core/theme/arl_colors.dart';
import 'package:arl_app/core/widgets/async_value_widget.dart';
import 'package:arl_app/core/mock/mock_data.dart'
    show MockSupportTicket, mockSupportTickets;

final _ticketsProvider = FutureProvider<List<dynamic>>((ref) async {
  final repo = ref.watch(supportRepositoryProvider);
  final real = await repo.myTickets();
  if (real.isNotEmpty) return real;
  return mockSupportTickets;
});

class SupportScreen extends ConsumerStatefulWidget {
  const SupportScreen({super.key});

  @override
  ConsumerState<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends ConsumerState<SupportScreen> {
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    // DEF-2026-05-15-03: subscribe to support_tickets changes so
    // ops-driven status flips propagate without a manual refresh.
    // Filtered to the current investor's own rows by RLS — the
    // anon JWT scopes Realtime payloads automatically.
    final client = ArlSupabase.client;
    final uid = client?.auth.currentUser?.id;
    if (client != null && uid != null) {
      _channel = client.channel('support_tickets_realtime_$uid')
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'support_tickets',
          callback: (_) {
            if (mounted) ref.invalidate(_ticketsProvider);
          },
        )
        ..subscribe();
    }
  }

  @override
  void dispose() {
    final ch = _channel;
    if (ch != null) {
      ArlSupabase.client?.removeChannel(ch);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dateFormatter = DateFormat('MMM dd, yyyy');
    final asyncTickets = ref.watch(_ticketsProvider);

    return Scaffold(
      backgroundColor: ArlColors.cream,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: ArlColors.charcoal),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(RouteNames.home);
            }
          },
        ),
        title: const Text(
          'Assistance',
          style: TextStyle(
            color: ArlColors.charcoal,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => context.push(RouteNames.newTicket),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ArlColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Raise a Ticket',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'My Tickets',
                style: TextStyle(
                  color: ArlColors.charcoal,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              AsyncValueWidget(
                value: asyncTickets,
                onRetry: () => ref.invalidate(_ticketsProvider),
                data: (rows) {
                  if (rows.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'No tickets yet.',
                        style: TextStyle(color: ArlColors.muted, fontSize: 12),
                      ),
                    );
                  }
                  return Column(
                    children: [
                      for (final raw in rows)
                        _ticketCard(
                          context,
                          raw: raw,
                          dateFormatter: dateFormatter,
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ticketCard(
    BuildContext context, {
    required dynamic raw,
    required DateFormat dateFormatter,
  }) {
    final id = raw is MockSupportTicket ? raw.id : (raw['id'] ?? '').toString();
    // DEF-2026-05-15-12: render UUIDs as a short prefix (matches the
    // HTML design + the in-bell ticket reference). Mock IDs are
    // already in short "TKT-NNNN" form; only real UUIDs need
    // trimming. The full UUID is still in the route + detail title.
    final isUuid = id.length >= 36 && id.contains('-');
    final displayId = isUuid ? '#${id.substring(0, 8)}' : id;
    final subject = raw is MockSupportTicket
        ? raw.subject
        : (raw['subject'] ?? '').toString();
    final status = raw is MockSupportTicket
        ? raw.status
        : (raw['status'] ?? 'open').toString();
    final createdAt = raw is MockSupportTicket
        ? raw.createdAt
        : (raw['created_at'] != null
            ? DateTime.parse(raw['created_at'].toString())
            : DateTime.now());
    final isResolved = status.toLowerCase() == 'resolved';
    final isDemo = raw is MockSupportTicket;

    return GestureDetector(
      onTap: () => context.push('/ticket/$id'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: ArlColors.sand, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      displayId,
                      style: const TextStyle(
                        color: ArlColors.charcoal,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (isDemo)
                      Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: ArlColors.gold.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: ArlColors.gold.withValues(alpha: 0.4),
                            width: 0.6,
                          ),
                        ),
                        child: const Text(
                          'Sample',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: Color(0xFF8C7300),
                          ),
                        ),
                      ),
                  ],
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isResolved
                        ? ArlColors.accent.withValues(alpha: 0.15)
                        : ArlColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      color: isResolved ? ArlColors.accent : ArlColors.primary,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              subject,
              style: const TextStyle(color: ArlColors.charcoal, fontSize: 11),
            ),
            const SizedBox(height: 6),
            Text(
              dateFormatter.format(createdAt),
              style: const TextStyle(color: ArlColors.muted, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}
