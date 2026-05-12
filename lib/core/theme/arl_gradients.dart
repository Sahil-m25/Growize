import 'package:flutter/material.dart';
import 'arl_colors.dart';

abstract final class ArlGradients {
  // gradient-primary: linear-gradient(145deg, #3C5152 0%, #2A5E50 100%)
  static const LinearGradient primary = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    stops: [0.0, 1.0],
    colors: [ArlColors.primary, Color(0xFF2A5E50)],
    transform: GradientRotation(145 * 3.14159 / 180),
  );

  // gradient-gold: linear-gradient(145deg, #D4AF37 0%, #F2DC6B 100%)
  static const LinearGradient gold = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    stops: [0.0, 1.0],
    colors: [ArlColors.gold, ArlColors.goldLight],
    transform: GradientRotation(145 * 3.14159 / 180),
  );

  // Portfolio card inner tint: linear-gradient(to right, #3C5152, #2E7D6E)
  static const LinearGradient progressBar = LinearGradient(
    colors: [ArlColors.primary, ArlColors.accent],
  );

  // Per-project progress bar gradients matching HTML PROGRESS_DATA.barColor
  static const LinearGradient progressGv = LinearGradient(
    colors: [Color(0xFF3C5152), Color(0xFF2E7D6E)],
  );
  static const LinearGradient progressSo = LinearGradient(
    colors: [Color(0xFF5C3D11), Color(0xFFA0522D)],
  );
  static const LinearGradient progressVa = LinearGradient(
    colors: [Color(0xFF2D4A5E), Color(0xFF4A7A9B)],
  );
}
