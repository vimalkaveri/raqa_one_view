// ==========================
// File: fsa_color_mapper.dart
// Maps a decoded FSA register value to a status colour.
// ==========================

import 'package:flutter/material.dart';

Color getFSARegisterColor(String name, String value) {
  final v = value.toLowerCase();

  switch (name) {
    case "Device ID":
    case "Version":
      return Colors.grey;

    case "Z1 Config":
    case "Z2 Config":
      return v == "open" ? Colors.lightBlue : Colors.blueAccent;

    case "Z1 Status":
    case "Z2 Status":
      return v == "fire" ? Colors.red : Colors.green;

    case "Device Status":
      switch (v) {
        case "fire":
          return Colors.red;
        case "silent":
          return const Color(0xFF7003FA);
        case "healthy":
          return Colors.green;
        default:
          return Colors.grey;
      }

    case "Power Status":
      return v == "main" ? Colors.green : Colors.orange;

    case "Siren Status":
      return v == "on" ? Colors.green : Colors.grey;

    case "Relay Status":
      return v == "on" ? Colors.green : Colors.grey;

    default:
      return Colors.grey;
  }
}
