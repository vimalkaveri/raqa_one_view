// ==========================
// File: mlp_color_mapper.dart
// Maps a decoded MLP register value to a status colour.
// ==========================

import 'package:flutter/material.dart';

Color getMLPRegisterColor(String name, String value) {
  final v = value.toLowerCase();

  /// ---------- CONFIG (NO / NC) ----------
  if (name.contains("Config")) {
    switch (v) {
      case "nc":
        return Colors.blue;
      case "no":
        return Colors.cyan;
      default:
        return Colors.grey;
    }
  }

  /// ---------- INPUT ----------
  if (name.contains("Input")) {
    switch (v) {
      case "off":
        return Colors.grey;
      case "fault":
        return Colors.orange;
      case "fire":
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  /// ---------- ZONE STATUS ----------
  if (name.contains("Status") && name.startsWith("Z")) {
    switch (v) {
      case "healthy":
        return Colors.green;
      case "fault":
        return Colors.orange;
      case "fire":
        return Colors.red;
      case "recovered":
        return Colors.blueGrey;
      default:
        return Colors.grey;
    }
  }

  /// ---------- DEVICE STATUS ----------
  if (name == "Device Status") {
    switch (v) {
      case "healthy":
        return Colors.green;
      case "fault":
        return Colors.orange;
      case "fire":
        return Colors.red;
      case "recovered":
        return Colors.blueGrey;
      default:
        return Colors.grey;
    }
  }

  /// ---------- POWER ----------
  if (name == "Power Status") {
    switch (v) {
      case "main":
        return Colors.green;
      case "battery":
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  /// ---------- RELAY ----------
  if (name.contains("Relay")) {
    return v == "on" ? Colors.red : Colors.grey;
  }

  /// ---------- HOOTER / SIREN ----------
  if (name.contains("Hooter") || name.contains("Siren")) {
    return v == "on" ? Colors.red : Colors.grey;
  }

  /// ---------- DEFAULT ----------
  return Colors.grey;
}
