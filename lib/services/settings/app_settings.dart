// ==========================
// File: services/settings/app_settings.dart
//
// Small persisted store for app-level (not per-slave) settings that are
// controlled from the Settings screen:
//   - sirenEnabled     : last commanded siren on/off state
//   - priorityEnabled  : whether the per-slave "priority" badge/behaviour
//                         (see ModbusRtu.slavePriorityMap) is active
//   - darkModeEnabled  : whether the app renders using the dark theme
//                         (default) or the light theme. Exposed as a
//                         ValueNotifier so MaterialApp can rebuild
//                         immediately when the Settings screen flips it,
//                         without any other app-wide state management.
//   - password         : simple app-lock password (plain text — this app
//                         has no login/auth backend, so this is a local
//                         PIN-style gate only, not a security boundary)
//
// Static, like ModbusRtu, so any screen can read/write it without needing
// to be handed an instance.
// ==========================

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  static bool sirenEnabled = false;
  static bool priorityEnabled = true;
  static String password = '';

  /// Whether the app is using the dark theme. Defaults to true, matching
  /// this app's original (and only, until now) look.
  static final ValueNotifier<bool> darkModeNotifier =
      ValueNotifier<bool>(true);
  static bool get darkModeEnabled => darkModeNotifier.value;

  /// Diameter (in logical pixels) of a sensor pin on the Dashboard floor
  /// plan. Adjustable from Settings so it can be tuned for screen size /
  /// viewing distance without touching code.
  static double pinSize = 44.0;
  static const double minPinSize = 18.0;
  static const double maxPinSize = 72.0;

  static const _kSiren = 'appSirenEnabled';
  static const _kPriorityEnabled = 'appPriorityEnabled';
  static const _kPassword = 'appPassword';
  static const _kPinSize = 'appPinSize';
  static const _kDarkMode = 'appDarkModeEnabled';

  ////////////////////////////////////////////////////////////
  // LOAD
  ////////////////////////////////////////////////////////////

  static Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    sirenEnabled = prefs.getBool(_kSiren) ?? sirenEnabled;
    priorityEnabled = prefs.getBool(_kPriorityEnabled) ?? priorityEnabled;
    password = prefs.getString(_kPassword) ?? password;
    pinSize = prefs.getDouble(_kPinSize) ?? pinSize;
    darkModeNotifier.value = prefs.getBool(_kDarkMode) ?? darkModeNotifier.value;
  }

  ////////////////////////////////////////////////////////////
  // SAVE (individual setters persist immediately so a screen doesn't
  // need to remember to call a bulk save)
  ////////////////////////////////////////////////////////////

  static Future<void> setSirenEnabled(bool value) async {
    sirenEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSiren, value);
  }

  static Future<void> setPriorityEnabled(bool value) async {
    priorityEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPriorityEnabled, value);
  }

  static Future<void> setPassword(String value) async {
    password = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPassword, value);
  }

  static Future<void> setPinSize(double value) async {
    pinSize = value.clamp(minPinSize, maxPinSize);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kPinSize, pinSize);
  }

  static Future<void> setDarkModeEnabled(bool value) async {
    darkModeNotifier.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kDarkMode, value);
  }
}
