import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../offline/offline_state.dart';
import '../theme/arl_colors.dart';

class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(isOnlineProvider);
    if (online) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: ArlColors.earth,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_off, color: Colors.white, size: 14),
          SizedBox(width: 6),
          Text('Offline — showing cached data', style: TextStyle(
            color: Colors.white, fontSize: 12, fontFamily: 'Inter',
          )),
        ],
      ),
    );
  }
}
