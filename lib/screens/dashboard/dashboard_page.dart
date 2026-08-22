// ==========================
// File: screens/dashboard/dashboard_page.dart
//
// The main Dashboard — layout follows the hand-drawn "Normal" state
// spec:
//
//   [ Date | Time | Status | Connected | Devices X/Y | Sensors X/Y | Offline ]
//   [ <  Floor 1  Floor 2  Floor 3  Floor 4  > ]
//   [ Floor N          |                                            ]
//   [  device          |        <floor plan image, live pins>       ]
//   [  Device 1         |                                            ]
//   [  Device 2         |                                            ]
//   [  Device 3         |                                            ]
//   [ Floor N          |                                            ]
//   [ Total device:.. |                                            ]
//   [ Total sensors:..|                                            ]
//
// Each "floor" is one SiteImageConfig from ConfigurationStore.history —
// the Dashboard lets you flip between all of them independently of
// whichever one the Configuration screen currently has "active" for
// editing.
//
// This covers the NORMAL / healthy-state layout only. The separate
// full-screen "Fire Alert" layout (fire-floor tabs + alerting device
// detail panel) is a follow-up once that spec is given.
//
// Also still handles: live pin colouring (from Modbus register decode),
// a looping fire-alarm buzzer with mute, and the app-lock password
// screen — all carried over from the previous single-floor version.
//
// NOTE: uses the `audioplayers` package for the alarm sound, and expects
// a `sounds/fire_alarm.mp3` asset declared in pubspec.yaml.
// ==========================

import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:vector_graphics/vector_graphics.dart';

import '../../devices/models/fsa/fsa_registers.dart';
import '../../devices/models/mlp/mlp_registers.dart';
import '../../devices/router/scan_device_signature.dart';
import '../../services/config/configuration_store.dart';
import '../../services/config/placed_sensor.dart';
import '../../services/config/sensor_type.dart';
import '../../services/config/site_image_config.dart';
import '../../services/rs485/modbus_rtu.dart';
import '../../services/rs485/rs485_service.dart';
import '../../services/settings/app_settings.dart';
import 'normal_dashboard.dart';
import 'fire_alert_dashboard.dart';

enum _PinLiveStatus { healthy, fault, fire, recovered, disabled, offline, unknown }

class DashboardScreen extends StatefulWidget {
  final Rs485Service manager;

  const DashboardScreen({super.key, required this.manager});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final ConfigurationStore _store = ConfigurationStore.instance;

  // Which floor tab is currently being viewed. Independent of
  // ConfigurationStore.activeIndex (that's "active for editing" on the
  // Configuration screen, this is "currently viewed" on the Dashboard).
  int _selectedFloorIndex = 0;

  // Fire-alert dashboard selection. This is intentionally independent from
  // the normal dashboard floor selection.
  int _selectedAlertFloorIndex = 0;

  final ScrollController _floorTabScrollController = ScrollController();

  PlacedSensor? _selectedSensor;

  DateTime _now = DateTime.now();

  // ---------------- LOCK ----------------

  late bool _locked = AppSettings.password.isNotEmpty;
  final TextEditingController _pinController = TextEditingController();
  String? _pinError;

  // ---------------- BUZZER ----------------

  static const String _buzzerAsset = 'sounds/fire_alarm.mp3';
  final AudioPlayer _buzzerPlayer = AudioPlayer();
  bool _isBuzzing = false;
  bool _isMuted = false;

  Timer? _tickTimer;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStoreChanged);

    // Drives the clock, the live pin colours/counts, and the buzzer
    // check. Register values arrive via manager.onStateChanged (already
    // wired to the app root), but that doesn't guarantee this pushed
    // route rebuilds, so this screen re-reads the latest snapshot itself
    // every second.
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _now = DateTime.now());
        _updateBuzzer();
      }
    });
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    _tickTimer?.cancel();
    _buzzerPlayer.dispose();
    _pinController.dispose();
    _floorTabScrollController.dispose();
    super.dispose();
  }

  void _onStoreChanged() {
    if (!mounted) return;
    if (_selectedFloorIndex >= _store.history.length) {
      _selectedFloorIndex =
          _store.history.isEmpty ? 0 : _store.history.length - 1;
    }
    if (_selectedAlertFloorIndex >= _store.history.length) {
      _selectedAlertFloorIndex =
          _store.history.isEmpty ? 0 : _store.history.length - 1;
    }
    setState(() {});
  }

  ////////////////////////////////////////////////////////////
  /// LIVE STATUS
  ////////////////////////////////////////////////////////////

  _PinLiveStatus _statusFor(PlacedSensor sensor) {
    if (widget.manager.isSlaveOffline(sensor.slaveId)) {
      return _PinLiveStatus.offline;
    }

    final index = sensor.slaveId - 1;
    if (index < 0 || index >= widget.manager.slaveRegistersNotifier.length) {
      return _PinLiveStatus.unknown;
    }

    final registers = widget.manager.slaveRegistersNotifier[index].value;

    int? rawValue;
    for (final r in registers) {
      if (r.address == sensor.zoneAddress) {
        rawValue = r.value;
        break;
      }
    }
    if (rawValue == null) return _PinLiveStatus.unknown;

    final type = ModbusRtu.slaveTypeMap[sensor.slaveId] ?? DeviceType.fsa;
    final decoded = type == DeviceType.fsa
        ? decodeFSARegisterValue(sensor.zoneAddress, rawValue)
        : decodeMLPRegisterValue(sensor.zoneAddress, rawValue);

    switch (decoded.toLowerCase()) {
      case 'healthy':
        return _PinLiveStatus.healthy;
      case 'fault':
        return _PinLiveStatus.fault;
      case 'fire':
        return _PinLiveStatus.fire;
      case 'recovered':
        return _PinLiveStatus.recovered;
      case 'disable':
        return _PinLiveStatus.disabled;
      default:
        return _PinLiveStatus.unknown;
    }
  }

  Color _colorFor(_PinLiveStatus status) {
    switch (status) {
      case _PinLiveStatus.healthy:
        return Colors.green;
      case _PinLiveStatus.fault:
        return Colors.orange;
      case _PinLiveStatus.fire:
        return Colors.red;
      case _PinLiveStatus.recovered:
        return Colors.blueGrey;
      case _PinLiveStatus.disabled:
        return Colors.grey;
      case _PinLiveStatus.offline:
        return Colors.grey.shade700;
      case _PinLiveStatus.unknown:
        return Colors.grey;
    }
  }

  IconData _iconFor(PlacedSensor sensor, _PinLiveStatus status) {
    if (status == _PinLiveStatus.offline) return Icons.wifi_off;
    return sensor.type.icon;
  }

  bool get _anyFireAnywhere {
    for (final floor in _store.history) {
      for (final s in floor.sensors) {
        if (_statusFor(s) == _PinLiveStatus.fire) return true;
      }
    }
    return false;
  }

  ////////////////////////////////////////////////////////////
  /// COUNTS
  ////////////////////////////////////////////////////////////

  // Global — every configured/scanned slave, regardless of whether it's
  // been placed on a floor plan yet.
  int get _globalDevicesTotal => ModbusRtu.slaveIds.length;

  int get _globalDevicesOnline => ModbusRtu.slaveIds
      .where((id) => !widget.manager.isSlaveOffline(id))
      .length;

  // Global — every placed sensor pin across every floor.
  int get _globalSensorsTotal =>
      _store.history.fold(0, (sum, f) => sum + f.sensors.length);

  int get _globalSensorsOnline => _store.history.fold(0, (sum, f) {
        return sum +
            f.sensors
                .where((s) => !widget.manager.isSlaveOffline(s.slaveId))
                .length;
      });

  // Per-floor — devices/sensors placed on the currently viewed floor only.
  SiteImageConfig? get _currentFloor =>
      (_selectedFloorIndex >= 0 && _selectedFloorIndex < _store.history.length)
          ? _store.history[_selectedFloorIndex]
          : null;

  Set<int> _floorDeviceIds(SiteImageConfig floor) =>
      floor.sensors.map((s) => s.slaveId).toSet();

  int _floorDevicesOnline(SiteImageConfig floor) => _floorDeviceIds(floor)
      .where((id) => !widget.manager.isSlaveOffline(id))
      .length;

  int _floorSensorsOnline(SiteImageConfig floor) => floor.sensors
      .where((s) => !widget.manager.isSlaveOffline(s.slaveId))
      .length;

  ////////////////////////////////////////////////////////////
  /// BUZZER (loops while any placed sensor, on any floor, reports Fire)
  ////////////////////////////////////////////////////////////

  Future<void> _updateBuzzer() async {
    final shouldBuzz = _anyFireAnywhere && !_isMuted;

    if (shouldBuzz && !_isBuzzing) {
      _isBuzzing = true;
      try {
        await _buzzerPlayer.setReleaseMode(ReleaseMode.loop);
        await _buzzerPlayer.play(AssetSource(_buzzerAsset));
      } catch (e) {
        debugPrint('⚠️ Could not play buzzer sound: $e');
        _isBuzzing = false;
      }
    } else if (!shouldBuzz && _isBuzzing) {
      _isBuzzing = false;
      try {
        await _buzzerPlayer.stop();
      } catch (e) {
        debugPrint('⚠️ Could not stop buzzer sound: $e');
      }
    }
  }

  void _toggleMute() {
    setState(() => _isMuted = !_isMuted);
    _updateBuzzer();
  }

  ////////////////////////////////////////////////////////////
  /// LOCK SCREEN
  ////////////////////////////////////////////////////////////

  void _attemptUnlock() {
    if (_pinController.text == AppSettings.password) {
      setState(() {
        _locked = false;
        _pinError = null;
        _pinController.clear();
      });
    } else {
      setState(() => _pinError = 'Incorrect password');
    }
  }

  Widget _buildLockScreen() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock, size: 56, color: Colors.tealAccent),
            const SizedBox(height: 16),
            const Text(
              'Dashboard Locked',
              style: TextStyle(color: Colors.white, fontSize: 20),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _pinController,
              obscureText: true,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Password',
                errorText: _pinError,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _attemptUnlock(),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _attemptUnlock,
              child: const Text('Unlock'),
            ),
          ],
        ),
      ),
    );
  }

  ////////////////////////////////////////////////////////////
  /// UI
  ////////////////////////////////////////////////////////////

  @override
  Widget build(BuildContext context) {
    final fireAlert = _anyFireAnywhere;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _locked
            ? _buildLockScreen()
            : fireAlert
                ? _buildFireAlertDashboard()
                : NormalDashboardView(
                    topStatusBar: _buildTopStatusBar(),
                    leftPanel: _buildLeftPanel(),
                    floorBody: _buildFloorBody(),
                    rightPanel: _buildRightPanel(),
                    bottomSummary: _buildBottomSummary(),
                    emptyState: _buildEmptyState(),
                    hasFloors: _store.history.isNotEmpty,
                  ),
      ),
    );
  }

  ////////////////////////////////////////////////////////////
  /// FIRE ALERT DASHBOARD
  ////////////////////////////////////////////////////////////

  List<SiteImageConfig> get _fireFloors => _store.history
      .where(
        (floor) => floor.sensors.any(
          (sensor) => _statusFor(sensor) == _PinLiveStatus.fire,
        ),
      )
      .toList();

  SiteImageConfig? get _selectedAlertFloor {
    final floors = _fireFloors;
    if (floors.isEmpty) return null;

    final index = _selectedAlertFloorIndex.clamp(0, floors.length - 1);
    return floors[index];
  }

  PlacedSensor? _alertSensorForFloor(SiteImageConfig floor) {
    final selected = _selectedSensor;
    if (selected != null &&
        floor.sensors.contains(selected) &&
        _statusFor(selected) == _PinLiveStatus.fire) {
      return selected;
    }

    for (final sensor in floor.sensors) {
      if (_statusFor(sensor) == _PinLiveStatus.fire) {
        return sensor;
      }
    }
    return null;
  }

  Widget _buildFireAlertDashboard() {
    final fireFloors = _fireFloors;
    if (fireFloors.isEmpty) {
      return const SizedBox.shrink();
    }

    final selectedFloor = _selectedAlertFloor ?? fireFloors.first;
    final alertSensor = _alertSensorForFloor(selectedFloor);

    return FireAlertDashboardView(
      topStatusBar: _buildTopStatusBar(alertMode: true),
      fireFloors: fireFloors,
      selectedFloorIndex: _selectedAlertFloorIndex.clamp(0, fireFloors.length - 1),
      onFloorSelected: (index) {
        setState(() {
          _selectedAlertFloorIndex = index;
          _selectedSensor = null;
        });
      },
      selectedFloor: selectedFloor,
      floorBody: _buildFloorBody(floorOverride: selectedFloor),
      alertDeviceDetails: _buildAlertDeviceDetails(alertSensor, selectedFloor),
    );
  }


  Widget _buildAlertDeviceDetails(
    PlacedSensor? sensor,
    SiteImageConfig floor,
  ) {
    return Container(
      height: 68,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF161616),
        border: Border(
          top: BorderSide(color: Colors.redAccent),
        ),
      ),
      child: sensor == null
          ? const Text(
              'Fire device information unavailable',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(
                  Icons.local_fire_department,
                  color: Colors.redAccent,
                  size: 30,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _alertDetailText(
                    'Device name',
                    sensor.name,
                  ),
                ),
                Expanded(
                  child: _alertDetailText(
                    'Sensor',
                    sensor.zoneLabel,
                  ),
                ),
                Expanded(
                  child: _alertDetailText(
                    'Location',
                    sensor.location,
                  ),
                ),
                Expanded(
                  child: _alertDetailText(
                    'Time',
                    '${_two(_now.hour)}:${_two(_now.minute)}:${_two(_now.second)}',
                  ),
                ),
                _statChip(
                  'FIRE',
                  color: Colors.redAccent,
                ),
              ],
            ),
    );
  }

  Widget _alertDetailText(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value.isEmpty ? '-' : value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  ////////////////////////////////////////////////////////////
  /// TOP STATUS BAR
  ////////////////////////////////////////////////////////////

  String _two(int n) => n.toString().padLeft(2, '0');

  Widget _statChip(String label, {Color? color}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: (color ?? Colors.white24), width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color ?? Colors.white70,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildTopStatusBar({bool alertMode = false}) {
    final isFire = alertMode || _anyFireAnywhere;

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        color: Color(0xFF121212),
        border: Border(
          bottom: BorderSide(color: Colors.white12),
        ),
      ),
      child: Row(
        children: [
          Text(
            isFire ? 'Fire Alert' : 'Normal',
            style: TextStyle(
              color: isFire ? Colors.redAccent : Colors.greenAccent,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: widget.manager.connectionStatus == 'Connected'
                    ? Colors.tealAccent
                    : Colors.orange,
              ),
            ),
            child: Text(
              widget.manager.connectionStatus,
              style: TextStyle(
                color: widget.manager.connectionStatus == 'Connected'
                    ? Colors.tealAccent
                    : Colors.orange,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Spacer(),
          Text(
            '${_two(_now.day)}/${_two(_now.month)}/${_now.year}',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(width: 16),
          Text(
            '${_two(_now.hour)}:${_two(_now.minute)}:${_two(_now.second)}',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(
              _isMuted ? Icons.volume_off : Icons.volume_up,
              color: Colors.white70,
            ),
            tooltip: _isMuted ? 'Unmute alarm' : 'Mute alarm',
            onPressed: _toggleMute,
          ),
          if (AppSettings.password.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.lock_outline, color: Colors.white70),
              tooltip: 'Lock dashboard',
              onPressed: () => setState(() => _locked = true),
            ),
        ],
      ),
    );
  }

  ////////////////////////////////////////////////////////////
  /// FLOOR TAB BAR
  ////////////////////////////////////////////////////////////

  Widget _buildFloorTabBar() {
    if (_store.history.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: const BoxDecoration(
        border: Border(
          right: BorderSide(color: Colors.white12),
          bottom: BorderSide(color: Colors.white12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Text(
              'Floor',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ...List.generate(_store.history.length, (index) {
            final floor = _store.history[index];
            final isSelected = index == _selectedFloorIndex;

            return InkWell(
              onTap: () => setState(() {
                _selectedFloorIndex = index;
                _selectedSensor = null;
              }),
              child: Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withOpacity(0.08)
                      : Colors.transparent,
                  border: Border(
                    left: BorderSide(
                      color: isSelected
                          ? Colors.tealAccent
                          : Colors.transparent,
                      width: 3,
                    ),
                  ),
                ),
                alignment: Alignment.centerLeft,
                child: Text(
                  floor.floorLabel,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white54,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 13,
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  ////////////////////////////////////////////////////////////
  /// LEFT PANEL — current floor's device list + floor stats
  ////////////////////////////////////////////////////////////

  Widget _buildLeftPanel() {
    final floor = _currentFloor;
    if (floor == null) return const SizedBox(width: 0);

    final deviceIds = _floorDeviceIds(floor).toList()..sort();
    final devicesTotal = deviceIds.length;
    final devicesOnline = _floorDevicesOnline(floor);

    return Container(
      width: 205,
      color: const Color(0xFF161616),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildFloorTabBar(),
          const Divider(color: Colors.white12, height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Text(
              '${floor.floorLabel} device',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: floor.sensors.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'No sensors placed on this floor yet',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  )
                : ListView.builder(
                    itemCount: floor.sensors.length,
                    itemBuilder: (context, index) {
                      final sensor = floor.sensors[index];
                      final status = _statusFor(sensor);
                      final isSelected = _selectedSensor == sensor;

                      return ListTile(
                        dense: true,
                        selected: isSelected,
                        selectedTileColor: Colors.white.withOpacity(0.06),
                        leading: Icon(
                          _iconFor(sensor, status),
                          color: _colorFor(status),
                          size: 18,
                        ),
                        title: Text(
                          sensor.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                        subtitle: Text(
                          status.name,
                          style: TextStyle(
                            color: _colorFor(status).withOpacity(0.9),
                            fontSize: 10,
                          ),
                        ),
                        onTap: () => setState(() {
                          _selectedSensor = isSelected ? null : sensor;
                        }),
                      );
                    },
                  ),
          ),
          const Divider(color: Colors.white12, height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Devices: $devicesOnline/$devicesTotal online',
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFloorImageHeader() {
    final floor = _currentFloor;

    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.centerLeft,
      decoration: const BoxDecoration(
        color: Color(0xFF121212),
        border: Border(
          bottom: BorderSide(color: Colors.white12),
        ),
      ),
      child: Text(
        floor == null ? 'Floor image' : '${floor.floorLabel}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildRightPanel() {
    final offlineIds = ModbusRtu.slaveIds
        .where((id) => widget.manager.isSlaveOffline(id))
        .toList()
      ..sort();

    final floorsWithOfflineDevices = _store.history.where((floor) {
      return floor.sensors.any(
        (sensor) => widget.manager.isSlaveOffline(sensor.slaveId),
      );
    }).toList();

    return Container(
      width: 160,
      color: const Color(0xFF161616),
      padding: const EdgeInsets.fromLTRB(14, 14, 10, 10),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Status',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            _sideStat(
              'Devices',
              '$_globalDevicesOnline/$_globalDevicesTotal',
            ),
            const SizedBox(height: 8),
            _sideStat(
              'Sensor',
              '$_globalSensorsOnline/$_globalSensorsTotal',
            ),
            const SizedBox(height: 16),
            const Text(
              'Offline Device',
              style: TextStyle(
                color: Colors.orange,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            if (offlineIds.isEmpty)
              const Text(
                'None',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              )
            else
              ...offlineIds.map(
                (id) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    'Device $id',
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 14),
            const Text(
              'Floors affected',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            if (floorsWithOfflineDevices.isEmpty)
              const Text(
                'None',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              )
            else
              ...floorsWithOfflineDevices.map(
                (floor) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    floor.floorLabel,
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _sideStat(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildBottomSummary() {
    final floor = _currentFloor;
    if (floor == null) return const SizedBox.shrink();

    final devicesTotal = _floorDeviceIds(floor).length;
    final devicesOnline = _floorDevicesOnline(floor);
    final sensorsTotal = floor.sensors.length;
    final sensorsOnline = _floorSensorsOnline(floor);
    final sensorsOffline = sensorsTotal - sensorsOnline;

    return Container(
      height: 40,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Color(0xFF121212),
        border: Border(
          top: BorderSide(color: Colors.white12),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              floor.floorLabel,
              style: const TextStyle(
                color: Colors.tealAccent,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),

          const VerticalDivider(
            color: Colors.white12,
            width: 1,
          ),

          Expanded(
            child: Text(
              'Total device: $devicesTotal',
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 12,
              ),
            ),
          ),

          Expanded(
            child: Text(
              'Total sensor: $sensorsOnline/$sensorsTotal',
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 12,
              ),
            ),
          ),

          Expanded(
            child: Text(
              'Online: $devicesOnline',
              style: const TextStyle(
                color: Colors.greenAccent,
                fontSize: 12,
              ),
            ),
          ),

          Expanded(
            child: Text(
              'Offline: $sensorsOffline',
              style: const TextStyle(
                color: Colors.orangeAccent,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  ////////////////////////////////////////////////////////////
  /// EMPTY STATE (no floors configured at all)
  ////////////////////////////////////////////////////////////

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.image_outlined, size: 64, color: Colors.grey),
          SizedBox(height: 12),
          Text(
            'No floor plan configured yet',
            style: TextStyle(color: Colors.grey, fontSize: 16),
          ),
          SizedBox(height: 4),
          Text(
            'Load one from the Configuration screen',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }

  ////////////////////////////////////////////////////////////
  /// FLOOR BODY — the selected floor's image + live pins
  ////////////////////////////////////////////////////////////

  final Map<String, Size> _sizeCache = {};

  Future<Size> _resolveImageSize(String path) async {
    final cached = _sizeCache[path];
    if (cached != null) return cached;

    final info = await vg.loadPicture(SvgFileLoader(File(path)), null);
    info.picture.dispose();

    _sizeCache[path] = info.size;
    return info.size;
  }

  Widget _buildFloorBody({SiteImageConfig? floorOverride}) {
    final floor = floorOverride ?? _currentFloor;
    if (floor == null) return _buildEmptyState();

    return FutureBuilder<Size>(
      future: _resolveImageSize(floor.imagePath),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final imgSize = snapshot.data!;
        final aspectRatio = imgSize.width / imgSize.height;

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: AspectRatio(
                aspectRatio: aspectRatio,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            SvgPicture.file(File(floor.imagePath), fit: BoxFit.fill),
                            for (final sensor in floor.sensors)
                              _buildPin(sensor, constraints.biggest),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPin(PlacedSensor sensor, Size canvasSize) {
    const pinSize = 44.0;
    final status = _statusFor(sensor);
    final color = _colorFor(status);
    final isFire = status == _PinLiveStatus.fire;
    final isSelected = _selectedSensor == sensor;

    return Positioned(
      left: sensor.xFraction * canvasSize.width - pinSize / 2,
      top: sensor.yFraction * canvasSize.height - pinSize / 2,
      child: GestureDetector(
        onTap: () => setState(() {
          _selectedSensor = isSelected ? null : sensor;
        }),
        child: Tooltip(
          message:
              '${sensor.name} (${sensor.zoneLabel})\n${sensor.location}\n${status.name}',
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: pinSize,
            height: pinSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              border: isSelected
                  ? Border.all(color: Colors.white, width: 3)
                  : null,
              boxShadow: isFire
                  ? [
                      BoxShadow(
                        color: Colors.red.withOpacity(0.6),
                        blurRadius: 16,
                        spreadRadius: 4,
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              _iconFor(sensor, status),
              color: Colors.white,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}
