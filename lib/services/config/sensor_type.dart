// ==========================
// File: services/config/sensor_type.dart
//
// Generic sensor "kind" shown as a draggable icon in the Configuration
// screen's left rail. This is purely a display/category choice made at
// placement time — the pin is still always linked to an actual scanned
// Modbus slave (see PlacedSensor.slaveId), it just lets the user pick
// which icon represents that physical sensor on the floor plan.
// ==========================

import 'package:flutter/material.dart';

enum SensorType { fire, temperature }

extension SensorTypeUi on SensorType {
  IconData get icon {
    switch (this) {
      case SensorType.fire:
        return Icons.local_fire_department;
      case SensorType.temperature:
        return Icons.thermostat;
    }
  }

  String get label {
    switch (this) {
      case SensorType.fire:
        return 'Fire';
      case SensorType.temperature:
        return 'Temperature';
    }
  }

  Color get color {
    switch (this) {
      case SensorType.fire:
        return Colors.redAccent;
      case SensorType.temperature:
        return Colors.tealAccent;
    }
  }
}
