// lib/setting/device_color_mapper.dart

import 'package:flutter/material.dart';

import '../../devices/models/fsa/fsa_color_mapper.dart';
import '../../devices/models/mlp/mlp_color_mapper.dart';
import '../../devices/router/scan_device_signature.dart';


class DeviceColorMapper {
  static Color getColor(DeviceType type, String label, String value) {
    switch (type) {
      case DeviceType.fsa:
        return getFSARegisterColor(label, value);
      case DeviceType.mlp:
        return getMLPRegisterColor(label, value);
    }
  }

  ////////////////////////////////////////////////////////////
  /// PREVIEW REGISTER COUNT PER DEVICE
  ////////////////////////////////////////////////////////////

  static int getPreviewRegisterCount(DeviceType type) {
    switch (type) {
      case DeviceType.fsa:
        return 11;
      case DeviceType.mlp:
        return 15;
    }
  }
}
