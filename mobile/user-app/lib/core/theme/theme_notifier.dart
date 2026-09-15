import 'dart:async';

import 'package:flutter/material.dart';

import '../storage/app_preferences.dart';

class ThemeNotifier {
  static final ValueNotifier<ThemeMode> themeMode = ValueNotifier<ThemeMode>(
    ThemeMode.system,
  );
  static const _preferences = AppPreferencesStore();

  static Future<void> restore() async {
    try {
      final saved = await _preferences.readTheme();
      if (saved != null) _setThemeMode(saved);
    } catch (_) {
      // System theme remains the safe fallback when storage is unavailable.
    }
  }

  static void setTheme(String mode) {
    _setThemeMode(mode);
    unawaited(_persistTheme(themeString));
  }

  static void _setThemeMode(String mode) {
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

  static Future<void> _persistTheme(String theme) async {
    try {
      await _preferences.writeTheme(theme);
    } catch (_) {
      // Theme switching remains available for the current run.
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
