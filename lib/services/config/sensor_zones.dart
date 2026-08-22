// ==========================
// File: services/config/sensor_zones.dart
//
// A scanned device (one Modbus slave) can have more than one physical
// sensor wired to it — each zone register is a separate physical input,
// so each needs its own pin on the floor plan.
//
// Per current wiring:
//   - FSA : 2 zones -> Z1 Status (addr 5), Z2 Status (addr 6)
//   - MLP : 2 zones currently in use -> Z1 Status (addr 13), Z2 Status
//           (addr 14). MLP hardware supports 4 zones total, but only
//           zones 1-2 are wired/used right now — add Z3/Z4 back to this
//           list when that changes.
// ==========================

import '../../devices/router/scan_device_signature.dart';
import '../../devices/models/fsa/fsa_registers.dart';
import '../../devices/models/mlp/mlp_registers.dart';

class SensorZone {
  final int address;
  final String label;

  const SensorZone({required this.address, required this.label});
}

const Map<DeviceType, List<SensorZone>> deviceSensorZones = {
  DeviceType.fsa: [
    SensorZone(address: FSAAddresses.z1Status, label: 'Zone 1'),
    SensorZone(address: FSAAddresses.z2Status, label: 'Zone 2'),
  ],
  DeviceType.mlp: [
    SensorZone(address: MLPAddresses.z1Status, label: 'Zone 1'),
    SensorZone(address: MLPAddresses.z2Status, label: 'Zone 2'),
    SensorZone(address: MLPAddresses.z3Status, label: 'Zone 3'),
    SensorZone(address: MLPAddresses.z4Status, label: 'Zone 4'),
  ],
};

List<SensorZone> zonesForDeviceType(DeviceType type) =>
    deviceSensorZones[type] ?? const [];
