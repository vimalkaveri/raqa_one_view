// ==========================
// File: fsa_registers.dart
// Device Model: FSA
// ==========================

import '../../router/device_register.dart';

/// Register Address Constants
/// ⚠️ Modbus libraries usually use 0-based addressing
/// 0 → 40001, 1 → 40002, 2 → 40003, ...
class FSAAddresses {
  static const reserved = 0; // 40001
  static const deviceId = 1; // 40002
  static const version = 2; // 40003
  static const z1Config = 3; // 40004
  static const z2Config = 4; // 40005
  static const z1Status = 5; // 40006
  static const z2Status = 6; // 40007
  static const deviceStatus = 7; // 40008
  static const powerStatus = 8; // 40009
  static const sirenStatus = 9; // 40010
  static const relayStatus = 10; // 40011
}

/// 🔹 FSA Register List
const List<DeviceRegister> fsaRegisters = [
  DeviceRegister(address: FSAAddresses.reserved, name: "Reserved"),
  DeviceRegister(
    address: FSAAddresses.deviceId,
    name: "Device ID",
    valueMap: {21073: 'FSA-212R'},
  ),
  DeviceRegister(
    address: FSAAddresses.version,
    name: "Version",
    valueMap: {16641: 'A01'},
  ),
  DeviceRegister(
    address: FSAAddresses.z1Config,
    name: "Z1 Config",
    valueMap: {0: 'Close', 1: 'Open'},
  ),
  DeviceRegister(
    address: FSAAddresses.z2Config,
    name: "Z2 Config",
    valueMap: {0: 'Close', 1: 'Open'},
  ),
  DeviceRegister(
    address: FSAAddresses.z1Status,
    name: "Z1 Status",
    valueMap: {0: 'Healthy', 1: 'Fire'},
  ),
  DeviceRegister(
    address: FSAAddresses.z2Status,
    name: "Z2 Status",
    valueMap: {0: 'Healthy', 1: 'Fire'},
  ),
  DeviceRegister(
    address: FSAAddresses.deviceStatus,
    name: "Device Status",
    valueMap: {0: 'Healthy', 1: 'Fire', 2: 'Silent'},
  ),
  DeviceRegister(
    address: FSAAddresses.powerStatus,
    name: "Power Status",
    valueMap: {0: 'Main', 1: 'Battery'},
  ),
  DeviceRegister(
    address: FSAAddresses.sirenStatus,
    name: "Siren Status",
    valueMap: {0: 'Off', 1: 'On'},
  ),
  DeviceRegister(
    address: FSAAddresses.relayStatus,
    name: "Relay Status",
    valueMap: {0: 'Off', 1: 'On'},
  ),
];

/// Registers actually shown on the dashboard: everything after
/// Reserved / Device ID / Version. Computed once here and reused by every
/// FSA dashboard layout so all layouts stay in sync — previously each
/// layout file re-implemented this filter independently and several
/// (fsa_16) silently drifted from the rest.
final List<DeviceRegister> visibleFsaRegisters =
    fsaRegisters.where((r) => r.address > FSAAddresses.version).toList();

/// 🔎 Get register by address
DeviceRegister? getFSARegister(int address) {
  for (final r in fsaRegisters) {
    if (r.address == address) return r;
  }
  return null;
}

/// 🔎 Decode register value
String decodeFSARegisterValue(int address, int value) {
  return getFSARegister(address)?.decode(value) ?? value.toString();
}
