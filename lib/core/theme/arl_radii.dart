import 'package:flutter/material.dart';

abstract final class ArlRadii {
  // HTML uses rounded-[15px] uniformly on cards, buttons, inputs
  static const double card = 15;
  static const double pill = 999;
  static const double input = 15;
  static const double badge = 999;

  static const BorderRadius cardBorder = BorderRadius.all(Radius.circular(card));
  static const BorderRadius inputBorder = BorderRadius.all(Radius.circular(input));
}
