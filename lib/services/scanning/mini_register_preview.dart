// lib/setting/mini_register_preview.dart

import 'package:flutter/material.dart';


import '../../devices/router/device_model.dart';
import '../../devices/router/scan_device_signature.dart';
import '../rs485/rs485_register_data.dart';
import '../rs485/rs485_service.dart';
import 'device_color_mapper.dart';

class DeviceRegisterPreview extends StatelessWidget {
  final Rs485Service manager;
  final int slaveIndex; // IMPORTANT: this must be slaveId - 1
  final DeviceType type;

  const DeviceRegisterPreview({
    super.key,
    required this.manager,
    required this.slaveIndex,
    required this.type,
  });

  @override
  Widget build(BuildContext context) {
    final model = DeviceModels.getByType(type);

    if (slaveIndex < 0 || slaveIndex >= manager.slaveRegistersNotifier.length) {
      return const SizedBox();
    }

    final notifier = manager.slaveRegistersNotifier[slaveIndex];

    return ValueListenableBuilder<List<RegisterData>>(
      valueListenable: notifier,
      builder: (context, registers, _) {
        if (registers.isEmpty) {
          return const SizedBox();
        }

        final previewCount = DeviceColorMapper.getPreviewRegisterCount(type);

        final previewRegisters = model.registers.length > 3
            ? model.registers.skip(3).take(previewCount).toList()
            : <dynamic>[];

        return GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          itemCount: previewRegisters.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 8,
            mainAxisSpacing: 2,
            crossAxisSpacing: 2,
          ),
          itemBuilder: (context, i) {
            final regMeta = previewRegisters[i];

            final register = registers.firstWhere(
              (r) => r.address == regMeta.address,
              orElse: () => RegisterData(
                address: regMeta.address,
                value: 0,
              ),
            );

            final rawValue = int.tryParse(register.value.toString()) ?? 0;

            final displayValue =
                regMeta.valueMap?[rawValue] ?? rawValue.toString();

            final color = DeviceColorMapper.getColor(
              type,
              regMeta.name,
              displayValue,
            );

            return Container(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            );
          },
        );
      },
    );
  }
}
