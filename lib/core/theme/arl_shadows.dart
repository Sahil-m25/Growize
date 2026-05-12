import 'package:flutter/material.dart';

abstract final class ArlShadows {
  // .card-shadow: 0 2px 8px rgba(60,81,82,.08)
  static const List<BoxShadow> card = [
    BoxShadow(
      color: Color(0x143C5152),
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
  ];
}
