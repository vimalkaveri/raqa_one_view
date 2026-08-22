//lib/devices/router/scan_device_signature.dart

enum DeviceType {
  fsa,
  mlp,
}

class DeviceSignature {
  final String modelName; // RQ_A01
  final int r1;
  final int r2;
  final DeviceType type; // FSA / MLP / GRP

  const DeviceSignature({
    required this.modelName,
    required this.r1,
    required this.r2,
    required this.type,
  });
}
