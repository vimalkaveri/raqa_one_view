// ==========================
// File: services/config/configuration_store.dart
//
// Holds the Configuration page's state: every image loaded this session
// ("history") and which one is currently active.
//
// Persisted to SharedPreferences (mirroring the old project's
// SensorRepository) so a placed floor plan + its sensor pins survive an
// app restart, in addition to being swappable within a session via
// image history.
//
// A ChangeNotifier singleton (like ModbusRtu is a static singleton) so
// the Configuration screen can rebuild via AnimatedBuilder/ListenableBuilder
// without threading state through constructors.
// ==========================

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'placed_sensor.dart';
import 'sensor_type.dart';
import 'site_image_config.dart';

class ConfigurationStore extends ChangeNotifier {
  ConfigurationStore._internal();

  static final ConfigurationStore instance = ConfigurationStore._internal();

  static const _kHistory = 'configHistoryV1';
  static const _kActiveIndex = 'configActiveIndexV1';

  final List<SiteImageConfig> history = [];
  int activeIndex = -1;

  SiteImageConfig? get active =>
      (activeIndex >= 0 && activeIndex < history.length)
          ? history[activeIndex]
          : null;

  ////////////////////////////////////////////////////////////
  // LOAD / SAVE (SharedPreferences)
  ////////////////////////////////////////////////////////////

  Future<void> loadFromDisk() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kHistory);

    history.clear();
    activeIndex = prefs.getInt(_kActiveIndex) ?? -1;

    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as List;
        history.addAll(decoded.map((e) => _configFromJson(e)));
      } catch (_) {
        // Corrupt/old data -- start clean rather than crash.
        history.clear();
        activeIndex = -1;
      }
    }

    if (activeIndex < -1 || activeIndex >= history.length) {
      activeIndex = history.isEmpty ? -1 : history.length - 1;
    }

    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(history.map(_configToJson).toList());
    await prefs.setString(_kHistory, encoded);
    await prefs.setInt(_kActiveIndex, activeIndex);
  }

  Map<String, dynamic> _configToJson(SiteImageConfig c) => {
        'id': c.id,
        'imagePath': c.imagePath,
        'loadedAt': c.loadedAt.toIso8601String(),
        'floorLabel': c.floorLabel,
        'sensors': c.sensors.map(_sensorToJson).toList(),
      };

  SiteImageConfig _configFromJson(Map<String, dynamic> json) => SiteImageConfig(
        id: json['id']?.toString() ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        imagePath: json['imagePath']?.toString() ?? '',
        loadedAt: DateTime.tryParse(json['loadedAt']?.toString() ?? '') ??
            DateTime.now(),
        floorLabel: json['floorLabel']?.toString() ?? 'Floor',
        sensors: ((json['sensors'] as List?) ?? const [])
            .map((e) => _sensorFromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> _sensorToJson(PlacedSensor s) => {
        'slaveId': s.slaveId,
        'zoneAddress': s.zoneAddress,
        'zoneLabel': s.zoneLabel,
        'type': s.type.name,
        'name': s.name,
        'location': s.location,
        'notes': s.notes,
        'xFraction': s.xFraction,
        'yFraction': s.yFraction,
      };

  PlacedSensor _sensorFromJson(Map<String, dynamic> json) => PlacedSensor(
        slaveId: (json['slaveId'] as num?)?.toInt() ?? 0,
        zoneAddress: (json['zoneAddress'] as num?)?.toInt() ?? 0,
        zoneLabel: json['zoneLabel']?.toString() ?? '',
        type: SensorType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => SensorType.fire,
        ),
        name: json['name']?.toString() ?? 'Sensor',
        location: json['location']?.toString() ?? '',
        notes: json['notes']?.toString() ?? '',
        xFraction: (json['xFraction'] as num?)?.toDouble() ?? 0,
        yFraction: (json['yFraction'] as num?)?.toDouble() ?? 0,
      );

  ////////////////////////////////////////////////////////////
  // LOAD / SWAP IMAGE
  ////////////////////////////////////////////////////////////

  /// Adds a newly-picked image and makes it the active one. Auto-labelled
  /// "Floor N" by load order — rename via [renameFloor] afterwards.
  void addImage(String path) {
    history.add(
      SiteImageConfig(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        imagePath: path,
        loadedAt: DateTime.now(),
        floorLabel: 'Floor ${history.length + 1}',
      ),
    );
    activeIndex = history.length - 1;
    notifyListeners();
    _persist();
  }

  /// Swaps the active image to a previously loaded one (history is kept,
  /// nothing is discarded).
  void setActive(String id) {
    final index = history.indexWhere((c) => c.id == id);
    if (index == -1) return;
    activeIndex = index;
    notifyListeners();
    _persist();
  }

  /// Renames the floor tab label for [id] (shown on the Dashboard's floor
  /// tab bar and the Configuration image-history sheet).
  void renameFloor(String id, String label) {
    final trimmed = label.trim();
    if (trimmed.isEmpty) return;
    final index = history.indexWhere((c) => c.id == id);
    if (index == -1) return;
    history[index].floorLabel = trimmed;
    notifyListeners();
    _persist();
  }

  ////////////////////////////////////////////////////////////
  // SENSOR PLACEMENT (applies to the active image only).
  // A pin is identified by (slaveId, zoneAddress) -- one slave can have
  // several zones, each with its own pin.
  ////////////////////////////////////////////////////////////

  PlacedSensor? sensorForZone(int slaveId, int zoneAddress) {
    final cfg = active;
    if (cfg == null) return null;
    for (final s in cfg.sensors) {
      if (s.slaveId == slaveId && s.zoneAddress == zoneAddress) return s;
    }
    return null;
  }

  /// All zones already placed for a given slave, on the active image.
  List<PlacedSensor> sensorsForSlave(int slaveId) {
    final cfg = active;
    if (cfg == null) return const [];
    return cfg.sensors.where((s) => s.slaveId == slaveId).toList();
  }

  void addOrUpdateSensor(PlacedSensor sensor) {
    final cfg = active;
    if (cfg == null) return;

    final idx = cfg.sensors.indexWhere(
      (s) => s.slaveId == sensor.slaveId && s.zoneAddress == sensor.zoneAddress,
    );
    if (idx >= 0) {
      cfg.sensors[idx] = sensor;
    } else {
      cfg.sensors.add(sensor);
    }
    notifyListeners();
    _persist();
  }

  void removeSensor(int slaveId, int zoneAddress) {
    final cfg = active;
    if (cfg == null) return;
    cfg.sensors.removeWhere(
      (s) => s.slaveId == slaveId && s.zoneAddress == zoneAddress,
    );
    notifyListeners();
    _persist();
  }
}
