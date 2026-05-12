import 'package:flutter/material.dart';

abstract final class ArlColors {
  // Brand palette — matches Growize App Design
  static const Color primary   = Color(0xFF3C5152); // deep forest green
  static const Color gold      = Color(0xFFD4AF37); // harvest gold
  static const Color goldLight = Color(0xFFF2DC6B); // lighter gold (#F2DC6B from HTML arl-goldlight)
  static const Color accent    = Color(0xFF2E7D6E); // operational green (#2E7D6E from HTML arl-accent)
  static const Color arlGreen  = accent;            // alias — kept for back-compat
  static const Color cream     = Color(0xFFFAFAF7); // off-white background
  static const Color sand      = Color(0xFFE1DFC6); // warm sand
  static const Color earth     = Color(0xFFC05640); // terracotta
  static const Color charcoal  = Color(0xFF0F1A15); // near-black text
  static const Color muted     = Color(0xFF6B7280); // secondary text
  static const Color white     = Colors.white;

  // Semantic aliases
  static const Color background = cream;
  static const Color cardBg     = white;
  static const Color divider    = sand;
  static const Color success    = Color(0xFF22C55E);
  static const Color error      = earth;
}
