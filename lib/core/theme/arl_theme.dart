import 'package:flutter/material.dart';
import 'arl_colors.dart';

final ThemeData arlTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: ArlColors.primary,
    primary: ArlColors.primary,
    secondary: ArlColors.gold,
    surface: ArlColors.cream,
    error: ArlColors.earth,
  ),
  scaffoldBackgroundColor: ArlColors.cream,
  fontFamily: 'Inter',
  appBarTheme: const AppBarTheme(
    backgroundColor: ArlColors.cream,
    foregroundColor: ArlColors.charcoal,
    elevation: 0,
    scrolledUnderElevation: 0,
    centerTitle: false,
    titleTextStyle: TextStyle(
      fontFamily: 'Inter',
      fontSize: 18,
      fontWeight: FontWeight.w700,
      color: ArlColors.charcoal,
    ),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: ArlColors.primary,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: const TextStyle(
        fontFamily: 'Inter',
        fontWeight: FontWeight.w600,
        fontSize: 14,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    ),
  ),
  cardTheme: const CardTheme(
    color: Colors.white,
    elevation: 0,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(15))),
    margin: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: ArlColors.sand),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: ArlColors.sand),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: ArlColors.primary, width: 1.5),
    ),
    labelStyle: const TextStyle(
      fontFamily: 'Inter',
      color: ArlColors.muted,
      fontSize: 14,
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  ),
  textTheme: const TextTheme(
    displayLarge: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, color: ArlColors.charcoal),
    displayMedium: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, color: ArlColors.charcoal),
    headlineLarge: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, color: ArlColors.charcoal),
    headlineMedium: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, color: ArlColors.charcoal),
    headlineSmall: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, color: ArlColors.charcoal),
    titleLarge: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, color: ArlColors.charcoal),
    titleMedium: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w500, color: ArlColors.charcoal),
    titleSmall: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w500, color: ArlColors.charcoal),
    bodyLarge: TextStyle(fontFamily: 'Inter', color: ArlColors.charcoal),
    bodyMedium: TextStyle(fontFamily: 'Inter', color: ArlColors.charcoal),
    bodySmall: TextStyle(fontFamily: 'Inter', color: ArlColors.muted),
    labelLarge: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600),
    labelMedium: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w500),
    labelSmall: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w500),
  ),
);
