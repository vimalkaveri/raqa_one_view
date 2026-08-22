
import 'package:raqa_one_view/services/rs485/rs485_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../devices/router/device_model.dart';
import '../../devices/router/scan_device_signature.dart';

class ModbusRtu {
  ////////////////////////////////////////////////////////////
  // RS485 SETTINGS
  ////////////////////////////////////////////////////////////

  static int baudRate = 9600;
  static int dataBits = 8;
  static int parity = 0;
  static int stopBits = 1;
  static int pollIntervalMs = 300;
  static const int functionCode = 3;

  ////////////////////////////////////////////////////////////
  // CONNECTION MANAGER
  ////////////////////////////////////////////////////////////

  static late Rs485Service connectionManager;

  ////////////////////////////////////////////////////////////
  // SLAVES
  ////////////////////////////////////////////////////////////

  static List<int> slaveIds = [];

  static Map<int, String> slaveNames = {};
  static Map<int, String> slaveModelMap = {}; // display only
  static Map<int, DeviceType> slaveTypeMap = {}; // routing

  /// User-assigned priority order, set from the Devices screen when
  /// editing a scanned slave. Optional — a slave with no entry here has
  /// no priority and shows no badge. Only ever changed by
  /// [setPriorityForSlave] or [clearPriorityForSlave] — never
  /// auto-assigned, so a device's priority is stable across rescans
  /// unless the user changes it.
  static Map<int, int> slavePriorityMap = {};

  ////////////////////////////////////////////////////////////
  // PREF KEYS
  ////////////////////////////////////////////////////////////

  static const _kSlaveIds = 'slaveIds';
  static const _kBaudRate = 'baudRate';
  static const _kDataBits = 'dataBits';
  static const _kStopBits = 'stopBits';
  static const _kParity = 'parity';
  static const _kPollIntervalMs = 'pollIntervalMs';
  static const _kSlaveNames = 'slaveNames';
  static const _kSlaveModels = 'slaveModels';
  static const _kSlaveTypes = 'slaveTypes';
  static const _kSlavePriorities = 'slavePriorities';

  ////////////////////////////////////////////////////////////
  // LOAD SETTINGS
  ////////////////////////////////////////////////////////////

  static Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    baudRate = prefs.getInt(_kBaudRate) ?? baudRate;
    dataBits = prefs.getInt(_kDataBits) ?? dataBits;
    stopBits = prefs.getInt(_kStopBits) ?? stopBits;
    parity = prefs.getInt(_kParity) ?? parity;
    pollIntervalMs = prefs.getInt(_kPollIntervalMs) ?? pollIntervalMs;

    ////////////////////////////////////////////////////////////
    // SLAVE IDS
    ////////////////////////////////////////////////////////////

    slaveIds = prefs
        .getStringList(_kSlaveIds)
        ?.map((e) => int.tryParse(e))
        .where((v) => v != null && v >= 1 && v <= 247)
        .cast<int>()
        .toList() ??
        [];

    ////////////////////////////////////////////////////////////
    // SLAVE NAMES
    ////////////////////////////////////////////////////////////

    slaveNames.clear();
    final namesList = prefs.getStringList(_kSlaveNames);

    if (namesList != null) {
      for (final entry in namesList) {
        final parts = entry.split('|');
        if (parts.length == 2) {
          final id = int.tryParse(parts[0]);
          if (id != null) {
            slaveNames[id] = parts[1];
          }
        }
      }
    }

    ////////////////////////////////////////////////////////////
    // SLAVE MODELS (DISPLAY)
    ////////////////////////////////////////////////////////////

    slaveModelMap.clear();
    final modelList = prefs.getStringList(_kSlaveModels);

    if (modelList != null) {
      for (final entry in modelList) {
        final parts = entry.split('|');
        if (parts.length == 2) {
          final id = int.tryParse(parts[0]);
          if (id != null) {
            slaveModelMap[id] = parts[1];
          }
        }
      }
    }

    ////////////////////////////////////////////////////////////
    // SLAVE TYPES (ROUTING)
    ////////////////////////////////////////////////////////////

    slaveTypeMap.clear();
    final typeList = prefs.getStringList(_kSlaveTypes);

    if (typeList != null) {
      for (final entry in typeList) {
        final parts = entry.split('|');
        if (parts.length == 2) {
          final id = int.tryParse(parts[0]);
          if (id != null) {
            slaveTypeMap[id] = DeviceType.values.firstWhere(
                  (e) => e.name == parts[1],
              orElse: () => DeviceType.fsa,
            );
          }
        }
      }
    }

    ////////////////////////////////////////////////////////////
    // SLAVE PRIORITIES (USER-ASSIGNED, OPTIONAL)
    ////////////////////////////////////////////////////////////

    slavePriorityMap.clear();
    final priorityList = prefs.getStringList(_kSlavePriorities);

    if (priorityList != null) {
      for (final entry in priorityList) {
        final parts = entry.split('|');
        if (parts.length == 2) {
          final id = int.tryParse(parts[0]);
          final priority = int.tryParse(parts[1]);
          if (id != null && priority != null) {
            slavePriorityMap[id] = priority;
          }
        }
      }
    }

    _prunePriorities();
  }

  ////////////////////////////////////////////////////////////
  // SAVE SETTINGS
  ////////////////////////////////////////////////////////////

  static Future<void> saveSettings() async {
    _prunePriorities();

    final prefs = await SharedPreferences.getInstance();

    await prefs.setInt(_kBaudRate, baudRate);
    await prefs.setInt(_kDataBits, dataBits);
    await prefs.setInt(_kStopBits, stopBits);
    await prefs.setInt(_kParity, parity);
    await prefs.setInt(_kPollIntervalMs, pollIntervalMs);

    await prefs.setStringList(
      _kSlaveIds,
      slaveIds.map((e) => e.toString()).toList(),
    );

    await prefs.setStringList(
      _kSlaveNames,
      slaveNames.entries.map((e) => '${e.key}|${e.value}').toList(),
    );

    await prefs.setStringList(
      _kSlaveModels,
      slaveModelMap.entries.map((e) => '${e.key}|${e.value}').toList(),
    );

    await prefs.setStringList(
      _kSlaveTypes,
      slaveTypeMap.entries.map((e) => '${e.key}|${e.value.name}').toList(),
    );

    await prefs.setStringList(
      _kSlavePriorities,
      slavePriorityMap.entries.map((e) => '${e.key}|${e.value}').toList(),
    );
  }

  ////////////////////////////////////////////////////////////
  // HELPERS
  ////////////////////////////////////////////////////////////

  /// Get device model (register structure)
  static DeviceModel getModelForSlave(int slaveId) {
    final type = slaveTypeMap[slaveId];
    if (type == null) return DeviceModels.fsa;
    return DeviceModels.getByType(type);
  }

  /// Get display name
  static String getDisplayName(int slaveId) {
    return slaveNames[slaveId] ?? "Slave $slaveId";
  }

  /// Get model display name
  static String getModelName(int slaveId) {
    return slaveModelMap[slaveId] ?? "Unknown";
  }

  /// Set slave device after scan
  static void registerSlaveDevice({
    required int slaveId,
    required DeviceSignature signature,
  }) {
    slaveModelMap[slaveId] = signature.modelName;
    slaveTypeMap[slaveId] = signature.type;

    if (!slaveIds.contains(slaveId)) {
      slaveIds.add(slaveId);
    }
  }

  /// Sets (or overwrites) the user-assigned priority for [slaveId] from
  /// the Devices screen's edit dialog, and persists it immediately —
  /// independent of the slave list/model "Save" button — so a priority
  /// change is never lost if the user backs out without saving the rest
  /// of the configuration.
  static Future<void> setPriorityForSlave(int slaveId, int priority) async {
    slavePriorityMap[slaveId] = priority;
    await _savePriorities();
  }

  /// Clears the priority for [slaveId] (the user left the field blank —
  /// this slave simply has no priority and shows no badge).
  static Future<void> clearPriorityForSlave(int slaveId) async {
    slavePriorityMap.remove(slaveId);
    await _savePriorities();
  }

  static Future<void> _savePriorities() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _kSlavePriorities,
      slavePriorityMap.entries.map((e) => '${e.key}|${e.value}').toList(),
    );
  }

  /// Drops any priority entries left over for slave IDs that are no
  /// longer part of the current configuration (e.g. a slave was
  /// unassigned or a different device now occupies that ID after a
  /// rescan), so stale priorities never resurface on an unrelated
  /// device. Called from [loadSettings] and [saveSettings].
  static void _prunePriorities() {
    slavePriorityMap.removeWhere((id, _) => !slaveIds.contains(id));
  }

  static int? priorityForSlave(int slaveId) => slavePriorityMap[slaveId];
}