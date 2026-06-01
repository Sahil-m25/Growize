import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:arl_app/core/constants/support_contacts.dart';
import 'package:arl_app/core/navigation/route_names.dart';
import 'package:arl_app/core/providers/repositories.dart';
import 'package:arl_app/core/supabase/supabase_client.dart';
import 'package:arl_app/core/theme/arl_colors.dart';
import 'package:arl_app/core/widgets/async_value_widget.dart';
import 'package:arl_app/core/mock/mock_data.dart'
    show MockSupportTicket, mockSupportTickets;
import 'package:arl_app/features/onboarding/tour_keys.dart';

/// WhatsApp green — matches the v2 HTML mockup spec (`#25D366`).
const _whatsappGreen = Color(0xFF25D366);

// RM + Tech numbers now live in `core/constants/support_contacts.dart`
// as `kRmPhone` / `kTechPhone` so every WhatsApp / tel: deep link in
// the app pulls from a single source of truth.

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
              // "Get help fast" header — matches HTML mockup section.
              const Text(
                'GET HELP FAST',
                style: TextStyle(
                  color: ArlColors.muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 8),
              _WhatsAppCta(
                key: TourKeys.supportWhatsappTech,
                title: 'WhatsApp Tech Support',
                subtitle: 'Quick reply for app issues',
                onTap: () => _openWhatsApp(
                  context,
                  phone: kTechPhone,
                  topic: 'tech',
                ),
              ),
              const SizedBox(height: 8),
              _WhatsAppCta(
                title: 'WhatsApp Your RM',
                subtitle: 'Account, payouts, investment queries',
                onTap: () => _openWhatsApp(
                  context,
                  phone: kRmPhone,
                  topic: 'rm',
                ),
              ),
              const SizedBox(height: 20),
              // Detailed Request card (demoted form CTA).
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: ArlColors.sand.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: ArlColors.sand),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: ArlColors.primary.withOpacity(0.10),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.description_outlined,
                        color: ArlColors.primary,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Detailed Request',
                            style: TextStyle(
                              color: ArlColors.charcoal,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'For less urgent matters · ~24h response',
                            style: TextStyle(
                              color: ArlColors.muted,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => context.push(RouteNames.newTicket),
                      style: TextButton.styleFrom(
                        backgroundColor:
                            ArlColors.primary.withOpacity(0.10),
                        foregroundColor: ArlColors.primary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      child: const Text(
                        'Open form',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
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
              color: Colors.black.withOpacity(0.06),
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
                          color: ArlColors.gold.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: ArlColors.gold.withOpacity(0.4),
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
                        ? ArlColors.accent.withOpacity(0.15)
                        : ArlColors.primary.withOpacity(0.15),
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

  /// Open WhatsApp with a pre-filled message routed to the right channel
  /// based on [topic]. Creates a Supabase ticket BEFORE opening WhatsApp
  /// so we have an audit trail even though the conversation happens off
  /// the app. If ticket creation fails we still open WhatsApp — the
  /// support flow takes priority over the audit log.
  Future<void> _openWhatsApp(
    BuildContext context, {
    required String phone,
    required String topic,
  }) async {
    final isTech = topic == 'tech';
    final preset = isTech
        ? 'Hi, this is a tech / app issue: '
        : 'Hi, I have a question about my Growize investment: ';
    // hybrid ticket: log the contact attempt so ops sees who reached out
    try {
      await ref.read(supportRepositoryProvider).createTicket(
            category: isTech ? 'tech' : 'rm',
            subject: isTech ? 'WhatsApp · Tech' : 'WhatsApp · RM',
            body: preset,
          );
    } catch (_) {
      // non-fatal — opening WhatsApp is the user's primary intent
    }
    final waUri = Uri.parse(
      'https://wa.me/${phone.replaceAll('+', '')}'
      '?text=${Uri.encodeComponent(preset)}',
    );
    final ok = await launchUrl(waUri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open WhatsApp')),
      );
    }
  }
}

/// WhatsApp CTA card — green icon disc on the left, title + subtitle in
/// the middle, chevron on the right.
class _WhatsAppCta extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _WhatsAppCta({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: ArlColors.sand),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: _whatsappGreen,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.chat_bubble_outline,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: ArlColors.charcoal,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: ArlColors.muted,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: ArlColors.muted,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}
