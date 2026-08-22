// ==========================
// File: mlp_registers.dart
// Device Model: MLP
// ==========================

import '../../router/device_register.dart';

/// Register Address Constants
/// ⚠️ Modbus libraries usually use 0-based addressing
/// 0 → 40001, 1 → 40002, 2 → 40003, ...
class MLPAddresses {
  static const reserved = 0; // 40001
  static const deviceId = 1; // 40002
  static const version = 2; // 40003
  static const pwrStatus = 3; // 40004
  static const devStatus = 4; // 40005
  static const z1Input = 5; // 40006
  static const z2Input = 6; // 40007
  static const z3Input = 7; // 40008
  static const z4Input = 8; // 40009
  static const z1Config = 9; // 40010
  static const z2Config = 10; // 40011
  static const z3Config = 11; // 40012
  static const z4Config = 12; // 40013
  static const z1Status = 13; // 40014
  static const z2Status = 14; // 40015
  static const z3Status = 15; // 40016
  static const z4Status = 16; // 40017
  static const rel1Status = 17; // 40018
  static const rel2Status = 18; // 40019
  static const rel3Status = 19; // 40020
  static const rel4Status = 20; // 40021
  static const htr1Status = 21; // 40022
  static const htr2Status = 22; // 40023
}

/// 🔹 MLP Register List
const List<DeviceRegister> mlpRegisters = [
  DeviceRegister(address: MLPAddresses.reserved, name: "Reserved"),
  DeviceRegister(
    address: MLPAddresses.deviceId,
    name: "Device ID",
    valueMap: {21073: 'MLP'},
  ),
  DeviceRegister(
    address: MLPAddresses.version,
    name: "Version",
    valueMap: {16641: 'A3'},
  ),
  DeviceRegister(
    address: MLPAddresses.pwrStatus,
    name: "Power Status",
    valueMap: {0: 'Main', 1: 'Battery'},
  ),
  DeviceRegister(
    address: MLPAddresses.devStatus,
    name: "Device Status",
    valueMap: {0: 'Healthy', 1: 'Fault', 2: 'Fire', 3: 'Recovered'},
  ),
  DeviceRegister(
    address: MLPAddresses.z1Input,
    name: "Z1 Input",
    valueMap: {0: 'Off', 1: 'Fault', 2: 'Fire'},
  ),
  DeviceRegister(
    address: MLPAddresses.z2Input,
    name: "Z2 Input",
    valueMap: {0: 'Off', 1: 'Fault', 2: 'Fire'},
  ),
  DeviceRegister(
    address: MLPAddresses.z3Input,
    name: "Z3 Input",
    valueMap: {0: 'Off', 1: 'Fault', 2: 'Fire'},
  ),
  DeviceRegister(
    address: MLPAddresses.z4Input,
    name: "Z4 Input",
    valueMap: {0: 'Off', 1: 'Fault', 2: 'Fire'},
  ),
  DeviceRegister(
    address: MLPAddresses.z1Config,
    name: "Z1 Config",
    valueMap: {0: 'NC', 1: 'NO'},
  ),
  DeviceRegister(
    address: MLPAddresses.z2Config,
    name: "Z2 Config",
    valueMap: {0: 'NC', 1: 'NO'},
  ),
  DeviceRegister(
    address: MLPAddresses.z3Config,
    name: "Z3 Config",
    valueMap: {0: 'NC', 1: 'NO'},
  ),
  DeviceRegister(
    address: MLPAddresses.z4Config,
    name: "Z4 Config",
    valueMap: {0: 'NC', 1: 'NO'},
  ),
  DeviceRegister(
    address: MLPAddresses.z1Status,
    name: "Z1 Status",
    valueMap: {
      0: 'Healthy',
      1: 'Fault',
      2: 'Fire',
      3: 'Recovered',
      255: 'Disable',
    },
  ),
  DeviceRegister(
    address: MLPAddresses.z2Status,
    name: "Z2 Status",
    valueMap: {
      0: 'Healthy',
      1: 'Fault',
      2: 'Fire',
      3: 'Recovered',
      255: 'Disable',
    },
  ),
  DeviceRegister(
    address: MLPAddresses.z3Status,
    name: "Z3 Status",
    valueMap: {
      0: 'Healthy',
      1: 'Fault',
      2: 'Fire',
      3: 'Recovered',
      255: 'Disable',
    },
  ),
  DeviceRegister(
    address: MLPAddresses.z4Status,
    name: "Z4 Status",
    valueMap: {
      0: 'Healthy',
      1: 'Fault',
      2: 'Fire',
      3: 'Recovered',
      255: 'Disable',
    },
  ),
  DeviceRegister(
    address: MLPAddresses.rel1Status,
    name: "Relay1 Status",
    valueMap: {0: 'Off', 1: 'On'},
  ),
  DeviceRegister(
    address: MLPAddresses.rel2Status,
    name: "Relay2 Status",
    valueMap: {0: 'Off', 1: 'On'},
  ),
  DeviceRegister(
    address: MLPAddresses.rel3Status,
    name: "Relay3 Status",
    valueMap: {0: 'Off', 1: 'On'},
  ),
  DeviceRegister(
    address: MLPAddresses.rel4Status,
    name: "Relay4 Status",
    valueMap: {0: 'Off', 1: 'On'},
  ),
  DeviceRegister(
    address: MLPAddresses.htr1Status,
    name: "Siren Status",
    valueMap: {0: 'Off', 1: 'On'},
  ),
  DeviceRegister(
    address: MLPAddresses.htr2Status,
    name: "Hooter Status",
    valueMap: {0: 'Off', 1: 'On'},
  ),
];

/// Standard visible set: everything after Reserved / Device ID / Version.
/// Used by the popup / 1 / 2 / 8 / 16 / 31 layouts.
final List<DeviceRegister> visibleMlpRegisters =
    mlpRegisters.where((r) => r.address > MLPAddresses.version).toList();

/// Compact visible set used only by the single-slave (1) layout, which has
/// enough screen space per slave that it additionally hides the raw
/// zone Input/Config registers and shows only the decoded Status registers.
/// This mirrors the original single-slave layout's intent but is now
/// documented and named instead of being an unlabelled inline filter.
final List<DeviceRegister> compactMlpRegisters = mlpRegisters.where((r) {
  final isHeader = r.address <= MLPAddresses.version;
  final isRawZoneDetail =
      r.address >= MLPAddresses.z1Input && r.address <= MLPAddresses.z4Config;
  return !isHeader && !isRawZoneDetail;
}).toList();

/// 🔎 Get register by address
DeviceRegister? getMLPRegister(int address) {
  for (final r in mlpRegisters) {
    if (r.address == address) return r;
  }
  return null;
}

/// 🔎 Decode register value
String decodeMLPRegisterValue(int address, int value) {
  return getMLPRegister(address)?.decode(value) ?? value.toString();
}
