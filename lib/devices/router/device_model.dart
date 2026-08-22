// ==========================
// File: devices/router/device_model.dart
// ==========================

import 'device_register.dart';
import 'scan_device_signature.dart';
import '../models/mlp/mlp_registers.dart';
import '../models/fsa/fsa_registers.dart';

////////////////////////////////////////////////////////////
/// 🔹 Device Model
////////////////////////////////////////////////////////////

class DeviceModel {
  final DeviceType type;
  final String modelName; // display purpose
  final int startAddress;
  final int quantity;
  final List<DeviceRegister> registers;

  const DeviceModel({
    required this.type,
    required this.modelName,
    required this.startAddress,
    required this.quantity,
    required this.registers,
  });
}

////////////////////////////////////////////////////////////
/// 🔹 Device Models Registry
////////////////////////////////////////////////////////////

class DeviceModels {
  ////////////////////////////////////////////////////////////
  // FSA
  ////////////////////////////////////////////////////////////

  static final DeviceModel fsa = DeviceModel(
    type: DeviceType.fsa,
    modelName: "FSA-212R",
    startAddress: 0,
    quantity: fsaRegisters.length,
    registers: fsaRegisters,
  );

  ////////////////////////////////////////////////////////////
  // MLP
  ////////////////////////////////////////////////////////////

  static final DeviceModel mlp = DeviceModel(
    type: DeviceType.mlp,
    modelName: "MLP-4052",
    startAddress: 0,
    quantity: mlpRegisters.length,
    registers: mlpRegisters,
  );


  ////////////////////////////////////////////////////////////
  // 🔥 MAP REGISTRY (O(1) lookup)
  ////////////////////////////////////////////////////////////

  static final Map<DeviceType, DeviceModel> _modelMap = {
    DeviceType.fsa: fsa,
    DeviceType.mlp: mlp,
  };

  ////////////////////////////////////////////////////////////
  // 🔹 Get model by DeviceType
  ////////////////////////////////////////////////////////////

  static DeviceModel getByType(DeviceType type) {
    return _modelMap[type] ?? fsa;
  }
}
