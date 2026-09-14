import 'package:flutter/material.dart';

class ThemeNotifier {
  static final ValueNotifier<ThemeMode> themeMode = ValueNotifier<ThemeMode>(
    ThemeMode.system,
  );

  static void setTheme(String mode) {
    switch (mode) {
      case 'light':
        themeMode.value = ThemeMode.light;
        break;
      case 'dark':
        themeMode.value = ThemeMode.dark;
        break;
      case 'system':
      default:
        themeMode.value = ThemeMode.system;
        break;
    }
  }

  static String get themeString {
    switch (themeMode.value) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }
}
