import 'package:flutter/material.dart';
import 'arl_colors.dart';

abstract final class ArlTextStyles {
  static const TextStyle h1 = TextStyle(
    fontFamily: 'Inter', fontSize: 28, fontWeight: FontWeight.w700,
    color: ArlColors.charcoal, letterSpacing: -0.5,
  );
  static const TextStyle h2 = TextStyle(
    fontFamily: 'Inter', fontSize: 22, fontWeight: FontWeight.w600,
    color: ArlColors.charcoal,
  );
  static const TextStyle h3 = TextStyle(
    fontFamily: 'Inter', fontSize: 18, fontWeight: FontWeight.w600,
    color: ArlColors.charcoal,
  );
  static const TextStyle body = TextStyle(
    fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w400,
    color: ArlColors.charcoal,
  );
  static const TextStyle bodyMuted = TextStyle(
    fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w400,
    color: ArlColors.muted,
  );
  static const TextStyle caption = TextStyle(
    fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w400,
    color: ArlColors.muted,
  );
  static const TextStyle label = TextStyle(
    fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w500,
    color: ArlColors.charcoal,
  );
  static const TextStyle button = TextStyle(
    fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
  );
  // Uppercase label with tracking — for "TOTAL PORTFOLIO VALUE" style headings
  static const TextStyle labelUpper = TextStyle(
    fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w600,
    color: ArlColors.muted, letterSpacing: 0.7,
  );
  // Light weight body text
  static const TextStyle bodyLight = TextStyle(
    fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w300,
    color: ArlColors.charcoal,
  );
  // Medium weight body text
  static const TextStyle bodyMedium = TextStyle(
    fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w500,
    color: ArlColors.charcoal,
  );
}
