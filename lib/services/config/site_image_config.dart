// ==========================
// File: services/config/site_image_config.dart
//
// One image loaded on the Configuration page ("Load Image"), plus the
// list of PlacedSensor pins the user has dropped on it. Multiple of
// these can exist (image history) — only one is ever "active" at a time,
// see ConfigurationStore.
// ==========================

import 'placed_sensor.dart';

class SiteImageConfig {
  final String id;
  final String imagePath;
  final DateTime loadedAt;
  final List<PlacedSensor> sensors;

  /// Display label for this image on the Dashboard's floor tab bar
  /// (e.g. "Floor 1"). Defaults to load order at creation time
  /// (ConfigurationStore.addImage) but can be renamed later.
  String floorLabel;

  SiteImageConfig({
    required this.id,
    required this.imagePath,
    required this.loadedAt,
    required this.floorLabel,
    List<PlacedSensor>? sensors,
  }) : sensors = sensors ?? [];
}
