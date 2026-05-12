import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arl_app/core/providers/repositories.dart';

final ticketByIdProvider =
    FutureProvider.family<Map<String, dynamic>?, String>(
  (ref, id) async {
    return ref.read(supportRepositoryProvider).ticketById(id);
  },
);

final ticketMessagesProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>(
  (ref, id) async {
    return ref.read(supportRepositoryProvider).messagesFor(id);
  },
);
