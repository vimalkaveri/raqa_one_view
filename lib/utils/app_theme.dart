// ==========================
// File: utils/app_theme.dart
//
// This app's screens paint their own backgrounds/text colors directly
// (Colors.black, Colors.white, etc.) rather than reading them from
// Theme.of(context) — that's the existing style throughout the codebase,
// and MaterialApp's theme/darkTheme mainly drives built-in widgets
// (AppBar, Switch, TextField underlines, dialogs, ...).
//
// AppTheme is the light/dark counterpart for that hand-painted styling:
// each screen's build() method reads these getters instead of hardcoding
// Colors.black / Colors.white, so it repaints correctly when
// AppSettings.darkModeEnabled flips. Values are chosen to match this
// app's existing dark palette (Colors.black scaffolds, #161616/#121212
// panels, teal accents) with an equivalent light counterpart, so toggling
// the setting doesn't change anything else about the app's structure.
//
// Not a full ThemeData-driven design system — just enough so "Dark Mode"
// in Settings actually re-themes every screen, not only new/isolated ones.
// ==========================

import 'package:flutter/material.dart';

import '../services/settings/app_settings.dart';

class AppTheme {
  AppTheme._();

  static bool get _dark => AppSettings.darkModeEnabled;

  /// Scaffold background.
  static Color get background => _dark ? Colors.black : const Color(0xFFF4F1F6);

  /// Rails / side panels / section backgrounds a shade up from [background].
  static Color get panel => _dark ? const Color(0xFF161616) : const Color(0xFFECE7EF);

  /// Cards / tiles a shade up from [panel].
  static Color get card => _dark ? const Color(0xFF121212) : Colors.white;

  /// Primary, high-contrast text/icon color.
  static Color get textPrimary => _dark ? Colors.white : Colors.black87;

  /// Secondary / caption / hint text color.
  static Color get textSecondary => _dark ? Colors.grey : Colors.black54;

  /// Hairline dividers between sections.
  static Color get divider => _dark ? Colors.white24 : Colors.black12;
}
