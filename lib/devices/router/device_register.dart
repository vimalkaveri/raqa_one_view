// ==========================
// File: devices/router/device_register.dart
//
// Shared register metadata model used by every device family
// (FSA / GRP / MLP).
//
// Previously each device family declared its own copy of this exact class
// (FSARegister, MLPRegister, GRPRegister) plus a fourth near-identical
// class lived in device_model.dart. All four were structurally identical.
// Unifying them here removes ~60 lines of duplicated, drift-prone code and
// means generic UI (RegisterGridDashboard, DeviceRegisterPreview) can work
// with any device family without per-family adapters.
// ==========================

class DeviceRegister {
  /// 0-based Modbus register address (0 == 40001).
  final int address;

  /// Human readable label shown on the dashboard.
  final String name;

  /// Optional raw-value -> readable-text lookup. When absent, the raw
  /// integer value is shown as-is.
  final Map<int, String>? valueMap;

  const DeviceRegister({
    required this.address,
    required this.name,
    this.valueMap,
  });

  /// Decode a raw register value into display text.
  String decode(int value) => valueMap?[value] ?? value.toString();
}
