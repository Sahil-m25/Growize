// Stub for Android / iOS / desktop. InlinePdfViewer is never instantiated
// on native — the caller always checks kIsWeb before routing here.
import 'package:flutter/material.dart';

class InlinePdfViewer extends StatelessWidget {
  final String url;
  const InlinePdfViewer({super.key, required this.url});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
