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
import 'package:flutter/services.dart';
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
import '../../utils/app_theme.dart';
import 'normal_dashboard.dart';
import 'fire_alert_dashboard.dart';

enum _PinLiveStatus { healthy, fault, fire, recovered, disabled, offline, unknown }

/// Paints two staggered expanding-and-fading rings, used behind any pin
/// currently reporting Fire. `progress` is the 0..1 animation value from
/// _rippleController; the 0.5 phase offset gives a continuous "radar"
/// ripple rather than a single ring popping in and out.
class _FireRipplePainter extends CustomPainter {
  final double progress;
  final Color color;

  const _FireRipplePainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxRadius = size.shortestSide / 2;

    for (final phase in [0.0, 0.5]) {
      final t = (progress + phase) % 1.0;
      final radius = maxRadius * (0.25 + t * 0.75);
      final opacity = (1 - t) * 0.55;

      final paint = Paint()
        ..color = color.withOpacity(opacity.clamp(0.0, 1.0))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;

      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _FireRipplePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}

class DashboardScreen extends StatefulWidget {
  final Rs485Service manager;

  const DashboardScreen({super.key, required this.manager});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with TickerProviderStateMixin {
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

  // Remote/keyboard focus tracking for pins on the floor-plan canvas.
  // Touch/mouse continue to use onTap; a D-pad/keyboard user instead
  // moves focus between pins (Flutter's built-in directional-focus
  // traversal handles that using each pin's on-screen position) and
  // presses Enter/Select to activate the focused pin, via the same
  // _toggleSensorSelection path a tap uses.
  //
  // Keyed by "slaveId_zoneAddress" (stable identity for a pin) rather
  // than the PlacedSensor instance itself, since edits replace the
  // instance via copyWith while the underlying pin stays the same.
  final Map<String, FocusNode> _pinFocusNodes = {};
  PlacedSensor? _focusedSensor;

  DateTime _now = DateTime.now();

  // ---------------- BUZZER ----------------

  static const String _buzzerAsset = 'sounds/fire_alarm.mp3';
  final AudioPlayer _buzzerPlayer = AudioPlayer();
  bool _isBuzzing = false;
  bool _isMuted = false;

  Timer? _tickTimer;

  // Drives the expanding ripple rings drawn behind any pin currently
  // reporting Fire. Runs continuously and independently of _tickTimer so
  // the ripple animates smoothly at frame rate rather than jumping once
  // a second.
  late final AnimationController _rippleController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  // First-seen timestamp for each pin currently reporting Fire, keyed the
  // same way as _pinFocusNodes ("slaveId_zoneAddress"). This is what the
  // Fire Alert panel's "Time" field shows — the moment that alert started,
  // not the live clock — so it stays fixed instead of ticking every second.
  final Map<String, DateTime> _fireAlertStartTimes = {};

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
        _updateFireAlertStartTimes();
      }
    });
  }

  /// Records the moment each pin first reports Fire, and clears it again
  /// once that pin is no longer on fire (so a later, separate alert on the
  /// same sensor gets its own fresh timestamp).
  void _updateFireAlertStartTimes() {
    final liveFireKeys = <String>{};

    for (final floor in _store.history) {
      for (final sensor in floor.sensors) {
        if (_statusFor(sensor) == _PinLiveStatus.fire) {
          final key = _pinKey(sensor);
          liveFireKeys.add(key);
          _fireAlertStartTimes.putIfAbsent(key, () => DateTime.now());
        }
      }
    }

    _fireAlertStartTimes.removeWhere((key, _) => !liveFireKeys.contains(key));
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    _tickTimer?.cancel();
    _rippleController.dispose();
    _buzzerPlayer.dispose();
    _floorTabScrollController.dispose();
    for (final node in _pinFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  ////////////////////////////////////////////////////////////
  /// PIN FOCUS / SELECTION (shared by remote D-pad and touch/mouse)
  ////////////////////////////////////////////////////////////

  String _pinKey(PlacedSensor sensor) =>
      '${sensor.slaveId}_${sensor.zoneAddress}';

  FocusNode _focusNodeFor(PlacedSensor sensor) {
    return _pinFocusNodes.putIfAbsent(
      _pinKey(sensor),
      () => FocusNode(debugLabel: 'pin_${_pinKey(sensor)}'),
    );
  }

  void _toggleSensorSelection(PlacedSensor sensor) {
    setState(() {
      _selectedSensor = (_selectedSensor == sensor) ? null : sensor;
    });
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
    _prunePinFocusNodes();
    setState(() {});
  }

  /// Drops focus nodes for pins that no longer exist on any floor (sensor
  /// removed via the Configuration screen), so the map doesn't grow
  /// unbounded across a long-lived Dashboard session.
  void _prunePinFocusNodes() {
    final liveKeys = <String>{
      for (final floor in _store.history)
        for (final sensor in floor.sensors) _pinKey(sensor),
    };

    final staleKeys =
        _pinFocusNodes.keys.where((k) => !liveKeys.contains(k)).toList();

    for (final key in staleKeys) {
      _pinFocusNodes.remove(key)?.dispose();
    }
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
  /// UI
  ////////////////////////////////////////////////////////////

  @override
  Widget build(BuildContext context) {
    final fireAlert = _anyFireAnywhere;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: fireAlert
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
      decoration: BoxDecoration(
        color: AppTheme.panel,
        border: const Border(
          top: BorderSide(color: Colors.redAccent),
        ),
      ),
      child: sensor == null
          ? Text(
              'Fire device information unavailable',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
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
                    _formatAlertStartTime(sensor),
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

  String _formatAlertStartTime(PlacedSensor sensor) {
    final start = _fireAlertStartTimes[_pinKey(sensor)];
    if (start == null) return '-';
    return '${_two(start.hour)}:${_two(start.minute)}:${_two(start.second)}';
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
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value.isEmpty ? '-' : value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppTheme.textPrimary,
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
        color: AppTheme.textPrimary.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: (color ?? AppTheme.divider), width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color ?? AppTheme.textSecondary,
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
      decoration: BoxDecoration(
        color: AppTheme.card,
        border: Border(
          bottom: BorderSide(color: AppTheme.divider),
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
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
          const SizedBox(width: 16),
          Text(
            '${_two(_now.hour)}:${_two(_now.minute)}:${_two(_now.second)}',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(
              _isMuted ? Icons.volume_off : Icons.volume_up,
              color: AppTheme.textSecondary,
            ),
            tooltip: _isMuted ? 'Unmute alarm' : 'Mute alarm',
            onPressed: _toggleMute,
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
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: AppTheme.divider),
          bottom: BorderSide(color: AppTheme.divider),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Text(
              'Floor',
              style: TextStyle(
                color: AppTheme.textPrimary,
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
                      ? AppTheme.textPrimary.withOpacity(0.08)
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
                    color: isSelected ? AppTheme.textPrimary : AppTheme.textSecondary,
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
      color: AppTheme.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildFloorTabBar(),
          Divider(color: AppTheme.divider, height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Text(
              '${floor.floorLabel} device',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: floor.sensors.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'No sensors placed on this floor yet',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
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
                        selectedTileColor: AppTheme.textPrimary.withOpacity(0.06),
                        leading: Icon(
                          _iconFor(sensor, status),
                          color: _colorFor(status),
                          size: 18,
                        ),
                        title: Text(
                          sensor.name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppTheme.textSecondary,
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
          Divider(color: AppTheme.divider, height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Devices: $devicesOnline/$devicesTotal online',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
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
      decoration: BoxDecoration(
        color: AppTheme.card,
        border: Border(
          bottom: BorderSide(color: AppTheme.divider),
        ),
      ),
      child: Text(
        floor == null ? 'Floor image' : '${floor.floorLabel}',
        style: TextStyle(
          color: AppTheme.textPrimary,
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
      color: AppTheme.panel,
      padding: const EdgeInsets.fromLTRB(14, 14, 10, 10),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Status',
              style: TextStyle(
                color: AppTheme.textPrimary,
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
              Text(
                'None',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
              )
            else
              ...offlineIds.map(
                (id) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    'Device $id',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 14),
            Text(
              'Floors affected',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            if (floorsWithOfflineDevices.isEmpty)
              Text(
                'None',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
              )
            else
              ...floorsWithOfflineDevices.map(
                (floor) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    floor.floorLabel,
                    style: TextStyle(
                      color: AppTheme.textSecondary,
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
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
        ),
        Text(
          value,
          style: TextStyle(
            color: AppTheme.textPrimary,
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
      decoration: BoxDecoration(
        color: AppTheme.card,
        border: Border(
          top: BorderSide(color: AppTheme.divider),
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

          VerticalDivider(
            color: AppTheme.divider,
            width: 1,
          ),

          Expanded(
            child: Text(
              'Total device: $devicesTotal',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
              ),
            ),
          ),

          Expanded(
            child: Text(
              'Total sensor: $sensorsOnline/$sensorsTotal',
              style: TextStyle(
                color: AppTheme.textSecondary,
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

  // Cache the actual SVG widget per floor image path. Without this,
  // SvgPicture.file(...) was being constructed fresh on every rebuild —
  // and since the Dashboard rebuilds every second (see _tickTimer), that
  // meant re-reading and re-parsing the floor-plan SVG off disk once a
  // second, forever, for as long as the Dashboard was open. That's
  // expensive work on the same UI isolate that also drives the RS-485
  // poll timer and serial-port input stream, so it could visibly delay
  // register updates while this screen was showing — even though actual
  // polling never stopped.
  final Map<String, Widget> _svgCache = {};

  Widget _svgFor(String path) {
    return _svgCache.putIfAbsent(
      path,
      () => SvgPicture.file(File(path), fit: BoxFit.fill),
    );
  }

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

    // If we've already resolved this floor's image size, skip the
    // FutureBuilder round-trip entirely and render synchronously — avoids
    // a one-frame "waiting" flicker on every per-second rebuild.
    final cachedSize = _sizeCache[floor.imagePath];
    if (cachedSize != null) {
      return _buildFloorImage(floor, cachedSize);
    }

    return FutureBuilder<Size>(
      future: _resolveImageSize(floor.imagePath),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return _buildFloorImage(floor, snapshot.data!);
      },
    );
  }

  Widget _buildFloorImage(SiteImageConfig floor, Size imgSize) {
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
                    color: AppTheme.textPrimary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _svgFor(floor.imagePath),
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
  }

  Widget _buildPin(PlacedSensor sensor, Size canvasSize) {
    // Pulled live from AppSettings (not cached) so a change made on the
    // Settings screen takes effect the next time this rebuilds — no need
    // to reopen the Dashboard.
    final pinSize = AppSettings.pinSize;
    final iconSize = pinSize * 0.5;
    // Bounding box for the ripple rings. Always allocated at this size
    // (even when not on fire) so the pin's anchor point doesn't shift
    // when it enters/exits a Fire state.
    final rippleBoxSize = pinSize * 3;

    final status = _statusFor(sensor);
    final color = _colorFor(status);
    final isFire = status == _PinLiveStatus.fire;
    final isSelected = _selectedSensor == sensor;
    final isFocused = _focusedSensor == sensor;

    return Positioned(
      key: ValueKey('pin_${_pinKey(sensor)}'),
      left: sensor.xFraction * canvasSize.width - rippleBoxSize / 2,
      top: sensor.yFraction * canvasSize.height - rippleBoxSize / 2,
      width: rippleBoxSize,
      height: rippleBoxSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (isFire)
            IgnorePointer(
              child: AnimatedBuilder(
                animation: _rippleController,
                builder: (context, _) => CustomPaint(
                  size: Size(rippleBoxSize, rippleBoxSize),
                  painter: _FireRipplePainter(
                    progress: _rippleController.value,
                    color: Colors.redAccent,
                  ),
                ),
              ),
            ),
          Focus(
            focusNode: _focusNodeFor(sensor),
            onFocusChange: (focused) {
              if (!mounted) return;
              setState(() => _focusedSensor = focused ? sensor : null);
            },
            onKeyEvent: (node, event) {
              if (event is! KeyDownEvent) return KeyEventResult.ignored;
              final key = event.logicalKey;
              if (key == LogicalKeyboardKey.enter ||
                  key == LogicalKeyboardKey.select ||
                  key == LogicalKeyboardKey.numpadEnter) {
                _toggleSensorSelection(sensor);
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: GestureDetector(
              onTap: () => _toggleSensorSelection(sensor),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
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
                          ? Border.all(color: AppTheme.textPrimary, width: 3)
                          : isFocused
                              ? Border.all(color: Colors.tealAccent, width: 2)
                              : null,
                      boxShadow: [
                        if (isFire)
                          BoxShadow(
                            color: Colors.red.withOpacity(0.6),
                            blurRadius: 16,
                            spreadRadius: 4,
                          ),
                        if (isFocused && !isSelected)
                          BoxShadow(
                            color: Colors.tealAccent.withOpacity(0.5),
                            blurRadius: 12,
                            spreadRadius: 2,
                          ),
                      ],
                    ),
                    child: Icon(
                      _iconFor(sensor, status),
                      color: AppTheme.textPrimary,
                      size: iconSize,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
