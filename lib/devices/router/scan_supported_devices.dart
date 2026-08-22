import '../router/scan_device_signature.dart';

class SupportedDevices {
  ////////////////////////////////////////////////////////////
  // SUPPORTED DEVICE LIST
  ////////////////////////////////////////////////////////////

  static const List<DeviceSignature> list = [
    DeviceSignature(
      modelName: "RQ_A01",
      r1: 0x5251,
      r2: 0x4101,
      type: DeviceType.fsa,
    ),
    DeviceSignature(
      modelName: "MLP",
      r1: 0x5251,
      r2: 0x4103,
      type: DeviceType.mlp,
    ),
  ];

  ////////////////////////////////////////////////////////////
  // LOOKUP MAP
  ////////////////////////////////////////////////////////////

  static final Map<String, DeviceSignature> _lookup = {
    for (var d in list) _key(d.r1, d.r2): d,
  };

  ////////////////////////////////////////////////////////////
  // BYTE SWAP HELPER
  ////////////////////////////////////////////////////////////

  static int _swap(int v) {
    return ((v & 0xFF) << 8) | ((v >> 8) & 0xFF);
  }

  ////////////////////////////////////////////////////////////
  // FIND DEVICE (ROBUST)
  ////////////////////////////////////////////////////////////

  static DeviceSignature? find(int r1, int r2) {
    final candidates = [
      (r1, r2),
      (_swap(r1), r2),
      (r1, _swap(r2)),
      (_swap(r1), _swap(r2)),
    ];

    for (final (a, b) in candidates) {
      final match = _lookup[_key(a, b)];
      if (match != null) return match;
    }

    return null;
  }

  ////////////////////////////////////////////////////////////
  // FIND BY NAME
  ////////////////////////////////////////////////////////////

  static DeviceSignature? findByName(String name) {
    try {
      return list.firstWhere((d) => d.modelName == name);
    } catch (_) {
      return null;
    }
  }

  ////////////////////////////////////////////////////////////
  // FILTER BY TYPE
  ////////////////////////////////////////////////////////////

  static List<DeviceSignature> getByType(DeviceType type) {
    return list.where((d) => d.type == type).toList();
  }

  ////////////////////////////////////////////////////////////
  // KEY
  ////////////////////////////////////////////////////////////

  static String _key(int r1, int r2) => "${r1}_$r2";
}
