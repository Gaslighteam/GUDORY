// Design tokens from the UI mock (AGENTS.md §6). Owned by the team lead.
import 'package:flutter/material.dart';

abstract final class AppColors {
  static const background = Color(0xFF000000);
  static const text = Color(0xFFFFFFFF);
  static const accent = Color(0xFFFFD60A); // selected zoom / armed shutter
  static const bubble = Color(0x8C000000); // rgba(0,0,0,0.55)
  static const chipSelected = Color(0x2EFFFFFF); // rgba(255,255,255,0.18)
  static const chipBorder = Color(0x66FFFFFF);
}

abstract final class AppText {
  static const body = 16.0;
  static const instruction = 18.0;
  static const chip = 15.0;
}

abstract final class AppRadius {
  static const bubble = 20.0;
  static const chip = 24.0;
}

ThemeData buildTheme() {
  return ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.accent,
      surface: AppColors.background,
      onSurface: AppColors.text,
    ),
    textTheme: const TextTheme(
      bodyMedium: TextStyle(fontSize: AppText.body, color: AppColors.text),
    ),
    useMaterial3: true,
  );
}
