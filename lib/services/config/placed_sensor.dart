// ==========================
// File: services/config/placed_sensor.dart
//
// A single physical sensor zone, pinned onto a Configuration-page image,
// at a fractional (0..1) position so the pin stays correctly placed
// regardless of how the image is scaled on screen.
//
// One scanned Modbus slave can have more than one zone wired to it (see
// sensor_zones.dart), so a pin is identified by (slaveId, zoneAddress)
// together, not slaveId alone.
// ==========================

import 'sensor_type.dart';

class PlacedSensor {
  /// Modbus slave ID — links this pin back to the scanned device in
  /// ModbusRtu.slaveIds / slaveModelMap.
  final int slaveId;

  /// Which zone register on that slave this pin represents (e.g. FSA
  /// Z1 Status = address 5). See sensor_zones.dart.
  final int zoneAddress;

  /// Display label for the zone, e.g. "Zone 1".
  final String zoneLabel;

  /// Which generic icon (fire/temperature/speed/signal) this pin shows.
  /// Chosen by which icon the user dragged from the rail — purely
  /// cosmetic/categorical, the link to the real sensor is
  /// [slaveId] + [zoneAddress].
  SensorType type;

  /// Editable display name for this sensor placement (defaults to the
  /// device's scanned model name + zone label).
  String name;

  /// Free-text location, e.g. "2nd Floor / Server Room".
  String location;

  /// Free-text notes.
  String notes;

  /// Position on the image, as a fraction of image width/height (0..1),
  /// so placement survives image resizing / different screen sizes.
  double xFraction;
  double yFraction;

  PlacedSensor({
    required this.slaveId,
    required this.zoneAddress,
    required this.zoneLabel,
    required this.type,
    required this.name,
    this.location = '',
    this.notes = '',
    required this.xFraction,
    required this.yFraction,
  });

  PlacedSensor copyWith({
    SensorType? type,
    String? name,
    String? location,
    String? notes,
    double? xFraction,
    double? yFraction,
  }) {
    return PlacedSensor(
      slaveId: slaveId,
      zoneAddress: zoneAddress,
      zoneLabel: zoneLabel,
      type: type ?? this.type,
      name: name ?? this.name,
      location: location ?? this.location,
      notes: notes ?? this.notes,
      xFraction: xFraction ?? this.xFraction,
      yFraction: yFraction ?? this.yFraction,
    );
  }
}
