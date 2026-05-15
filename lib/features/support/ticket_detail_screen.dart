import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:arl_app/core/navigation/route_names.dart';
import 'package:intl/intl.dart';
import 'package:arl_app/core/supabase/supabase_client.dart';
import 'package:arl_app/core/theme/arl_colors.dart';
import 'package:arl_app/core/widgets/skel_box.dart';
import 'package:arl_app/core/providers/repositories.dart';
import 'package:arl_app/features/support/ticket_provider.dart';

class TicketDetailScreen extends ConsumerStatefulWidget {
  final String ticketId;

  const TicketDetailScreen({
    required this.ticketId,
    super.key,
  });

  @override
  ConsumerState<TicketDetailScreen> createState() => _TicketDetailScreenState();
}

class _TicketDetailScreenState extends ConsumerState<TicketDetailScreen> {
  late TextEditingController _replyController;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _replyController = TextEditingController();
    // DEF-2026-05-15-03: Realtime subscription on ticket_messages
    // + support_tickets so staff replies and status flips render
    // without a manual refresh. Filter narrows to the current
    // ticket; RLS already restricts payloads to the investor.
    final client = ArlSupabase.client;
    if (client != null) {
      _channel = client.channel('ticket_realtime_${widget.ticketId}')
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'ticket_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'ticket_id',
            value: widget.ticketId,
          ),
          callback: (_) {
            if (mounted) {
              ref.invalidate(ticketMessagesProvider(widget.ticketId));
            }
          },
        )
        ..onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'support_tickets',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.ticketId,
          ),
          callback: (_) {
            if (mounted) {
              ref.invalidate(ticketByIdProvider(widget.ticketId));
            }
          },
        )
        ..subscribe();
    }
  }

  @override
  void dispose() {
    _replyController.dispose();
    final ch = _channel;
    if (ch != null) {
      ArlSupabase.client?.removeChannel(ch);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dateFormatter = DateFormat('MMM dd, yyyy · hh:mm a');
    final ticketAsync = ref.watch(ticketByIdProvider(widget.ticketId));
    final messagesAsync = ref.watch(ticketMessagesProvider(widget.ticketId));

    return Scaffold(
      backgroundColor: ArlColors.cream,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
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
        title: ticketAsync.when(
          loading: () => const Text(
            'Loading...',
            style: TextStyle(
              color: ArlColors.charcoal,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          error: (err, stack) => Text(
            '#${widget.ticketId}',
            style: const TextStyle(
              color: ArlColors.charcoal,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          data: (ticket) {
            if (ticket == null) {
              return Text(
                '#${widget.ticketId}',
                style: const TextStyle(
                  color: ArlColors.charcoal,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              );
            }

            final subject = ticket['subject'] as String? ?? '';
            final status = ticket['status'] as String? ?? '';

            final statusColor = _getStatusColor(status);

            return Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        subject,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: ArlColors.charcoal,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          status,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
        centerTitle: false,
      ),
      body: ticketAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: CircularProgressIndicator()),
        data: (ticket) {
          if (ticket == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Ticket not found'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => context.go(RouteNames.support),
                    child: const Text('Back to Support'),
                  ),
                ],
              ),
            );
          }

          final status = ticket['status'] as String? ?? '';
          final isResolved = status == 'resolved';

          return Column(
            children: [
              Expanded(
                child: messagesAsync.when(
                  loading: () => const Center(
                    child: CircularProgressIndicator(),
                  ),
                  error: (_, __) => const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: SkelBox(height: 120),
                    ),
                  ),
                  data: (messages) {
                    if (messages.isEmpty) {
                      return const Center(
                        child: Text('No messages yet'),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: messages.length,
                      itemBuilder: (context, idx) {
                        final msg = messages[idx];
                        final senderType = msg['sender_type'] as String? ?? '';
                        final body = msg['body'] as String? ?? '';
                        final createdAt = msg['created_at'] as String?;
                        final isInvestor = senderType == 'investor';

                        final formattedDate = createdAt != null
                            ? dateFormatter
                                .format(DateTime.parse(createdAt).toLocal())
                            : 'Unknown';

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _messageBubble(
                            isCustomer: isInvestor,
                            message: body,
                            date: formattedDate,
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: ArlColors.sand.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                child: isResolved
                    ? Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: ArlColors.accent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Center(
                          child: Text(
                            'This ticket is closed',
                            style: TextStyle(
                              color: ArlColors.accent,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _replyController,
                              decoration: InputDecoration(
                                hintText: 'Type your reply...',
                                hintStyle: const TextStyle(
                                  color: ArlColors.muted,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                              ),
                              maxLines: 1,
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(
                              Icons.send,
                              color: ArlColors.primary,
                            ),
                            onPressed: () => _sendReply(context),
                          ),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _sendReply(BuildContext context) async {
    final body = _replyController.text.trim();
    if (body.isEmpty) return;

    try {
      await ref
          .read(supportRepositoryProvider)
          .replyTicket(ticketId: widget.ticketId, body: body);

      _replyController.clear();
      ref.invalidate(ticketMessagesProvider(widget.ticketId));

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reply sent')),
      );
    } catch (e) {
      String errorMsg = 'Could not send reply. Try again.';
      bool shouldPop = false;
      if (e.toString().contains('400')) {
        errorMsg = 'This ticket is closed';
      } else if (e.toString().contains('404')) {
        errorMsg = 'Ticket not found';
        shouldPop = true;
      }
      if (!context.mounted) return;
      if (shouldPop) Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMsg)),
      );
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'open':
        return Colors.blue;
      case 'in_progress':
        return Colors.orange;
      case 'resolved':
        return ArlColors.accent;
      default:
        return ArlColors.muted;
    }
  }

  Widget _messageBubble({
    required bool isCustomer,
    required String message,
    required String date,
  }) {
    return Column(
      crossAxisAlignment:
          isCustomer ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isCustomer
                ? ArlColors.cream
                : Colors.green.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
            border: isCustomer ? Border.all(color: ArlColors.sand) : null,
          ),
          constraints: const BoxConstraints(maxWidth: 280),
          child: Text(
            message,
            style: const TextStyle(
              color: ArlColors.charcoal,
              fontSize: 11,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          date,
          style: const TextStyle(
            color: ArlColors.muted,
            fontSize: 9,
          ),
        ),
      ],
    );
  }
}
