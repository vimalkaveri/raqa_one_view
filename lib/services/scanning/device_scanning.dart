
// lib/scanner/scanner.dart

import 'dart:async';
import '../../devices/router/scan_device_signature.dart';
import '../../devices/router/scan_supported_devices.dart';
import '../rs485/modbus_rtu.dart';
import '../rs485/rs485_service.dart';

typedef ScanProgressCallback = void Function(
    int currentSlave,
    int totalSlaves,
    );

class DeviceScanning {
  final Rs485Service manager;

  DeviceScanning({required this.manager});

  ////////////////////////////////////////////////////////////
  // MAIN SCAN FUNCTION
  ////////////////////////////////////////////////////////////

  Future<Map<int, DeviceSignature>> scanSlaves({
    int startSlaveId = 1,
    int endSlaveId = 31,
    int retries = 0,
    Duration retryDelay = const Duration(milliseconds: 250),
    Duration responseTimeout = const Duration(milliseconds: 800),
    int startAddress = 0,
    int quantity = 3,
    ScanProgressCallback? onProgress,
  }) async {
    final Map<int, DeviceSignature> detectedDevices = {};

    if (manager.port == null) {
      print("RS485 not connected. Scan aborted.");
      return detectedDevices;
    }

    ////////////////////////////////////////////////////////////
    // CLEAR OLD DATA
    ////////////////////////////////////////////////////////////

    ModbusRtu.slaveIds.clear();
    ModbusRtu.slaveModelMap.clear();
    ModbusRtu.slaveTypeMap.clear();

    print("========== STARTING RS485 SCAN ==========");

    // Pause background polling for the *entire* scan, not per-slave --
    // otherwise, as soon as one slave matches and gets added to
    // ModbusRtu.slaveIds, the poll timer resumes mid-scan and races the
    // scan's own requests for the port, corrupting or starving most of
    // the remaining slaves' responses.
    await manager.beginManualScan();

    try {
      final totalSlaves = endSlaveId - startSlaveId + 1;
      int progressIndex = 0;

      for (int slaveId = startSlaveId; slaveId <= endSlaveId; slaveId++) {
        progressIndex++;

        onProgress?.call(progressIndex, totalSlaves);

        bool slaveFound = false;

        for (int attempt = 1; attempt <= retries + 1; attempt++) {
          try {
            print("Scanning Slave $slaveId (Attempt $attempt)");

            final values = await manager.readRegistersForScan(
              slaveId: slaveId,
              startAddress: startAddress,
              quantity: quantity,
              attempts: 1,
              timeout: responseTimeout,
            );

            if (values == null || values.length < 3) {
              print("Invalid response from Slave $slaveId");
              await Future.delayed(retryDelay);
              continue;
            }

            final int r1 = values[1];
            final int r2 = values[2];

            print(
              "Slave $slaveId Signature -> "
                  "r1=0x${r1.toRadixString(16).padLeft(4, '0')} "
                  "r2=0x${r2.toRadixString(16).padLeft(4, '0')}",
            );

            final DeviceSignature? matchedDevice = _matchDevice(r1, r2);

            if (matchedDevice == null) {
              print("Unknown device at Slave $slaveId");
              break;
            }

            print(
              "Matched Device at Slave $slaveId -> ${matchedDevice.modelName}",
            );

            ModbusRtu.registerSlaveDevice(
              slaveId: slaveId,
              signature: matchedDevice,
            );

            detectedDevices[slaveId] = matchedDevice;

            slaveFound = true;
            break;
          } catch (e) {
            print("Scan error Slave $slaveId: $e");
            await Future.delayed(retryDelay);
          }
        }

        if (!slaveFound) {
          print("Slave $slaveId not detected");
        }
      }

      await ModbusRtu.saveSettings();
    } finally {
      // Always resume polling, even if the scan throws partway through.
      manager.endManualScan();
    }

    print("========== SCAN COMPLETE ==========");
    print("Total Devices Found: ${detectedDevices.length}");

    return detectedDevices;
  }

  ////////////////////////////////////////////////////////////
  // DEVICE MATCHING
  ////////////////////////////////////////////////////////////

  DeviceSignature? _matchDevice(int r1, int r2) {
    for (final device in SupportedDevices.list) {
      if (device.r1 == r1 && device.r2 == r2) {
        return device;
      }
    }
    return null;
  }
}
