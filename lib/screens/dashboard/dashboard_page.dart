// ==========================
// File: screens/dashboard/dashboard_page.dart
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
import '../home_screen.dart';
import 'normal_dashboard.dart';
import 'fire_alert_dashboard.dart';

enum _PinLiveStatus {
  healthy,
  fault,
  fire,
  recovered,
  disabled,
  offline,
  unknown,
}

class _FireRipplePainter extends CustomPainter {
  final double progress;
  final Color color;

  const _FireRipplePainter({
    required this.progress,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxRadius = size.shortestSide / 2;

    for (final phase in [0.0, 0.5]) {
      final t = (progress + phase) % 1.0;
      final radius = maxRadius * (0.25 + t * 0.75);
      final opacity = (1 - t) * 0.55;

      final paint = Paint()
        ..color = color.withOpacity(
          opacity.clamp(0.0, 1.0),
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;

      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _FireRipplePainter oldDelegate) =>
      oldDelegate.progress != progress ||
          oldDelegate.color != color;
}

class DashboardScreen extends StatefulWidget {
  final Rs485Service manager;

  const DashboardScreen({
    super.key,
    required this.manager,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with TickerProviderStateMixin {
  final ConfigurationStore _store =
      ConfigurationStore.instance;

  // ==========================================================
  // FLOOR SELECTION
  // ==========================================================

  int _selectedFloorIndex = 0;

  int _selectedAlertFloorIndex = 0;

  final ScrollController _floorTabScrollController =
  ScrollController();

  // ==========================================================
  // TV REMOTE FOCUS
  // ==========================================================

  final List<FocusNode> _floorFocusNodes = [];

  final List<FocusNode> _deviceFocusNodes = [];

  final List<FocusNode> _alertFloorFocusNodes = [];

  int _focusedAlertFloorIndex = 0;

  final FocusNode _floorHeaderFocusNode =
  FocusNode(debugLabel: 'floor_header');

  int _focusedFloorIndex = 0;

  int _focusedDeviceIndex = 0;

  bool _focusIsOnDeviceList = false;

  // Device list scrolling
  final ScrollController _deviceScrollController =
  ScrollController();

  // ==========================================================
  // FIRE ALERT DEVICE CARDS (remote left/right navigation)
  // ==========================================================

  final List<FocusNode> _alertCardFocusNodes = [];

  int _focusedAlertCardIndex = 0;

  final ScrollController
  _alertCardScrollController =
  ScrollController();

  // ==========================================================
  // SENSOR SELECTION
  // ==========================================================

  PlacedSensor? _selectedSensor;

  final Map<String, FocusNode> _pinFocusNodes = {};

  PlacedSensor? _focusedSensor;

  // ==========================================================
  // CLOCK
  // ==========================================================

  DateTime _now = DateTime.now();

  // ==========================================================
  // BUZZER
  // ==========================================================

  static const String _buzzerAsset =
      'sounds/fire_alarm.mp3';

  final AudioPlayer _buzzerPlayer =
  AudioPlayer();

  bool _isBuzzing = false;
  bool _isMuted = false;

  Timer? _tickTimer;

  // ==========================================================
  // FIRE RIPPLE
  // ==========================================================

  late final AnimationController _rippleController =
  AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  // ==========================================================
  // FIRE START TIMES
  // ==========================================================

  final Map<String, DateTime>
  _fireAlertStartTimes = {};

  // ==========================================================
  // INIT
  // ==========================================================

  @override
  void initState() {
    super.initState();

    _store.addListener(_onStoreChanged);

    _tickTimer = Timer.periodic(
      const Duration(seconds: 1),
          (_) {
        if (!mounted) return;

        setState(() {
          _now = DateTime.now();
        });

        _updateBuzzer();
        _updateFireAlertStartTimes();
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupFocusNodes();
      _setupAlertFloorFocusNodes();

      if (_store.history.isNotEmpty) {
        _requestFloorFocus(0);
      }
    });
  }

  // ==========================================================
  // FOCUS NODE MANAGEMENT
  // ==========================================================

  void _setupFocusNodes() {
    final floorCount = _store.history.length;

    while (_floorFocusNodes.length < floorCount) {
      final index = _floorFocusNodes.length;

      _floorFocusNodes.add(
        FocusNode(
          debugLabel: 'floor_$index',
        ),
      );
    }

    while (_floorFocusNodes.length > floorCount) {
      _floorFocusNodes.removeLast().dispose();
    }

    final floor = _currentFloor;
    final deviceCount = floor?.sensors.length ?? 0;

    while (_deviceFocusNodes.length < deviceCount) {
      final index = _deviceFocusNodes.length;

      _deviceFocusNodes.add(
        FocusNode(
          debugLabel: 'device_$index',
        ),
      );
    }

    while (_deviceFocusNodes.length > deviceCount) {
      _deviceFocusNodes.removeLast().dispose();
    }
  }

  void _setupAlertFloorFocusNodes() {
    final floorCount = _fireFloors.length;

    while (_alertFloorFocusNodes.length < floorCount) {
      final index = _alertFloorFocusNodes.length;
      _alertFloorFocusNodes.add(
        FocusNode(debugLabel: 'alert_floor_$index'),
      );
    }

    while (_alertFloorFocusNodes.length > floorCount) {
      _alertFloorFocusNodes.removeLast().dispose();
    }

    if (floorCount == 0) {
      _focusedAlertFloorIndex = 0;
    } else if (_focusedAlertFloorIndex >= floorCount) {
      _focusedAlertFloorIndex = floorCount - 1;
    }
  }

  void _requestAlertFloorFocus(int index) {
    _setupAlertFloorFocusNodes();
    if (_alertFloorFocusNodes.isEmpty) return;

    final safeIndex = index.clamp(0, _alertFloorFocusNodes.length - 1);
    _focusedAlertFloorIndex = safeIndex;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || safeIndex >= _alertFloorFocusNodes.length) return;
      _alertFloorFocusNodes[safeIndex].requestFocus();
    });
  }

  void _onAlertFloorFocused(int index) {
    if (!mounted || index < 0 || index >= _fireFloors.length) return;
    setState(() {
      _focusedAlertFloorIndex = index;
    });
  }

  void _moveAlertFloorFocus(int index) {
    if (index < 0 || index >= _fireFloors.length) return;
    _requestAlertFloorFocus(index);
  }

  void _selectAlertFloor(int index) {
    if (index < 0 || index >= _fireFloors.length) return;

    setState(() {
      _selectedAlertFloorIndex = index;
      _focusedAlertFloorIndex = index;
      _selectedSensor = null;
    });

    _requestAlertFloorFocus(index);
  }

  void _setupAlertCardFocusNodes(
      int cardCount,
      ) {
    while (_alertCardFocusNodes.length <
        cardCount) {
      final index =
          _alertCardFocusNodes.length;

      _alertCardFocusNodes.add(
        FocusNode(
          debugLabel:
          'alert_card_$index',
        ),
      );
    }

    while (_alertCardFocusNodes.length >
        cardCount) {
      _alertCardFocusNodes
          .removeLast()
          .dispose();
    }

    if (_focusedAlertCardIndex >=
        cardCount) {
      _focusedAlertCardIndex =
          cardCount > 0
              ? cardCount - 1
              : 0;
    }
  }

  void _requestAlertCardFocus(
      int index,
      ) {
    if (_alertCardFocusNodes
        .isEmpty) {
      return;
    }

    final safeIndex = index.clamp(
      0,
      _alertCardFocusNodes.length - 1,
    );

    _focusedAlertCardIndex =
        safeIndex;

    WidgetsBinding.instance
        .addPostFrameCallback((_) {
      if (!mounted) return;

      _alertCardFocusNodes[safeIndex]
          .requestFocus();

      _scrollAlertCardIntoView(
        safeIndex,
      );
    });
  }

  void _scrollAlertCardIntoView(
      int index,
      ) {
    if (!_alertCardScrollController
        .hasClients) {
      return;
    }

    // Card width (420) + separator (10).
    const cardExtent = 430.0;

    final target =
        index * cardExtent;

    final viewport =
        _alertCardScrollController
            .position
            .viewportDimension;

    final current =
        _alertCardScrollController
            .offset;

    double? destination;

    if (target < current) {
      destination = target;
    } else if (target + cardExtent >
        current + viewport) {
      destination =
          target +
              cardExtent -
              viewport;
    }

    if (destination == null) return;

    destination = destination.clamp(
      0.0,
      _alertCardScrollController
          .position
          .maxScrollExtent,
    );

    _alertCardScrollController
        .animateTo(
      destination,
      duration: const Duration(
        milliseconds: 220,
      ),
      curve: Curves.easeOut,
    );
  }

  void _requestFloorFocus(int index) {
    if (_floorFocusNodes.isEmpty) return;

    final safeIndex =
    index.clamp(0, _floorFocusNodes.length - 1);

    _focusedFloorIndex = safeIndex;
    _focusIsOnDeviceList = false;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      _floorFocusNodes[safeIndex].requestFocus();

      _scrollFloorIntoView(safeIndex);
    });
  }

  void _requestDeviceFocus(int index) {
    if (_deviceFocusNodes.isEmpty) return;

    final safeIndex =
    index.clamp(0, _deviceFocusNodes.length - 1);

    _focusedDeviceIndex = safeIndex;
    _focusIsOnDeviceList = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      _deviceFocusNodes[safeIndex].requestFocus();

      _scrollDeviceIntoView(safeIndex);
    });
  }

  void _scrollFloorIntoView(int index) {
    if (!_floorTabScrollController.hasClients) {
      return;
    }

    final position = index * 38.0;

    _floorTabScrollController.animateTo(
      position.clamp(
        0.0,
        _floorTabScrollController.position.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
    );
  }

  void _scrollDeviceIntoView(int index) {
    if (!_deviceScrollController.hasClients) {
      return;
    }

    const itemHeight = 56.0;

    final target = index * itemHeight;

    final viewport =
        _deviceScrollController.position.viewportDimension;

    final currentOffset =
        _deviceScrollController.offset;

    final maxOffset =
        _deviceScrollController.position.maxScrollExtent;

    double newOffset = currentOffset;

    if (target < currentOffset) {
      newOffset = target;
    } else if (target + itemHeight >
        currentOffset + viewport) {
      newOffset = target +
          itemHeight -
          viewport;
    }

    newOffset = newOffset.clamp(
      0.0,
      maxOffset,
    );

    _deviceScrollController.animateTo(
      newOffset,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
    );
  }

  // ==========================================================
  // DISPOSE
  // ==========================================================

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);

    _tickTimer?.cancel();

    _rippleController.dispose();

    _buzzerPlayer.dispose();

    _floorTabScrollController.dispose();

    _deviceScrollController.dispose();

    _alertCardScrollController.dispose();

    _floorHeaderFocusNode.dispose();

    for (final node in _floorFocusNodes) {
      node.dispose();
    }

    for (final node in _alertFloorFocusNodes) {
      node.dispose();
    }

    for (final node in _deviceFocusNodes) {
      node.dispose();
    }

    for (final node in _alertCardFocusNodes) {
      node.dispose();
    }

    for (final node in _pinFocusNodes.values) {
      node.dispose();
    }

    super.dispose();
  }

  // ==========================================================
  // PIN FOCUS
  // ==========================================================

  String _pinKey(PlacedSensor sensor) =>
      '${sensor.slaveId}_${sensor.zoneAddress}';

  FocusNode _focusNodeFor(PlacedSensor sensor) {
    return _pinFocusNodes.putIfAbsent(
      _pinKey(sensor),
          () => FocusNode(
        debugLabel:
        'pin_${_pinKey(sensor)}',
      ),
    );
  }

  void _toggleSensorSelection(
      PlacedSensor sensor,
      ) {
    setState(() {
      _selectedSensor =
      (_selectedSensor == sensor)
          ? null
          : sensor;
    });
  }

  // ==========================================================
  // STORE CHANGES
  // ==========================================================

  void _onStoreChanged() {
    if (!mounted) return;

    if (_selectedFloorIndex >=
        _store.history.length) {
      _selectedFloorIndex =
      _store.history.isEmpty
          ? 0
          : _store.history.length - 1;
    }

    if (_selectedAlertFloorIndex >= _fireFloors.length) {
      _selectedAlertFloorIndex =
      _fireFloors.isEmpty ? 0 : _fireFloors.length - 1;
    }

    _prunePinFocusNodes();

    _setupFocusNodes();
    _setupAlertFloorFocusNodes();

    setState(() {});
  }

  void _prunePinFocusNodes() {
    final liveKeys = <String>{
      for (final floor in _store.history)
        for (final sensor in floor.sensors)
          _pinKey(sensor),
    };

    final staleKeys =
    _pinFocusNodes.keys
        .where(
          (key) =>
      !liveKeys.contains(key),
    )
        .toList();

    for (final key in staleKeys) {
      _pinFocusNodes
          .remove(key)
          ?.dispose();
    }
  }

  // ==========================================================
  // LIVE STATUS
  // ==========================================================

  _PinLiveStatus _statusFor(
      PlacedSensor sensor,
      ) {
    if (widget.manager
        .isSlaveOffline(sensor.slaveId)) {
      return _PinLiveStatus.offline;
    }

    final index = sensor.slaveId - 1;

    if (index < 0 ||
        index >=
            widget.manager
                .slaveRegistersNotifier
                .length) {
      return _PinLiveStatus.unknown;
    }

    final registers =
        widget.manager
            .slaveRegistersNotifier[index]
            .value;

    int? rawValue;

    for (final register in registers) {
      if (register.address ==
          sensor.zoneAddress) {
        rawValue = register.value;
        break;
      }
    }

    if (rawValue == null) {
      return _PinLiveStatus.unknown;
    }

    final type =
        ModbusRtu.slaveTypeMap[
        sensor.slaveId] ??
            DeviceType.fsa;

    final decoded =
    type == DeviceType.fsa
        ? decodeFSARegisterValue(
      sensor.zoneAddress,
      rawValue,
    )
        : decodeMLPRegisterValue(
      sensor.zoneAddress,
      rawValue,
    );

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

  Color _colorFor(
      _PinLiveStatus status,
      ) {
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

  IconData _iconFor(
      PlacedSensor sensor,
      _PinLiveStatus status,
      ) {
    if (status ==
        _PinLiveStatus.offline) {
      return Icons.wifi_off;
    }

    return sensor.type.icon;
  }

  bool get _anyFireAnywhere {
    for (final floor in _store.history) {
      for (final sensor in floor.sensors) {
        if (_statusFor(sensor) ==
            _PinLiveStatus.fire) {
          return true;
        }
      }
    }

    return false;
  }

  // ==========================================================
  // COUNTS
  // ==========================================================

  int get _globalDevicesTotal =>
      ModbusRtu.slaveIds.length;

  int get _globalDevicesOnline =>
      ModbusRtu.slaveIds
          .where(
            (id) =>
        !widget.manager
            .isSlaveOffline(id),
      )
          .length;

  int get _globalSensorsTotal =>
      _store.history.fold(
        0,
            (sum, floor) =>
        sum + floor.sensors.length,
      );

  int get _globalSensorsOnline =>
      _store.history.fold(
        0,
            (sum, floor) {
          return sum +
              floor.sensors
                  .where(
                    (sensor) =>
                !widget.manager
                    .isSlaveOffline(
                  sensor.slaveId,
                ),
              )
                  .length;
        },
      );

  SiteImageConfig? get _currentFloor =>
      (_selectedFloorIndex >= 0 &&
          _selectedFloorIndex <
              _store.history.length)
          ? _store.history[
      _selectedFloorIndex]
          : null;

  Set<int> _floorDeviceIds(
      SiteImageConfig floor,
      ) =>
      floor.sensors
          .map((sensor) => sensor.slaveId)
          .toSet();

  int _floorDevicesOnline(
      SiteImageConfig floor,
      ) {
    return _floorDeviceIds(floor)
        .where(
          (id) =>
      !widget.manager
          .isSlaveOffline(id),
    )
        .length;
  }

  int _floorSensorsOnline(
      SiteImageConfig floor,
      ) {
    return floor.sensors
        .where(
          (sensor) =>
      !widget.manager
          .isSlaveOffline(
        sensor.slaveId,
      ),
    )
        .length;
  }

  // ==========================================================
  // BUZZER
  // ==========================================================

  Future<void> _updateBuzzer() async {
    final shouldBuzz =
        _anyFireAnywhere &&
            !_isMuted &&
            AppSettings.sirenEnabled;

    if (shouldBuzz && !_isBuzzing) {
      _isBuzzing = true;

      try {
        await _buzzerPlayer
            .setReleaseMode(
          ReleaseMode.loop,
        );

        await _buzzerPlayer.play(
          AssetSource(_buzzerAsset),
        );
      } catch (e) {
        debugPrint(
          'Could not play buzzer: $e',
        );

        _isBuzzing = false;
      }
    } else if (!shouldBuzz &&
        _isBuzzing) {
      _isBuzzing = false;

      try {
        await _buzzerPlayer.stop();
      } catch (e) {
        debugPrint(
          'Could not stop buzzer: $e',
        );
      }
    }
  }

  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
    });

    _updateBuzzer();
  }

  // ==========================================================
  // FIRE START TIMES
  // ==========================================================

  void _updateFireAlertStartTimes() {
    final liveFireKeys = <String>{};

    for (final floor in _store.history) {
      for (final sensor in floor.sensors) {
        if (_statusFor(sensor) ==
            _PinLiveStatus.fire) {
          final key = _pinKey(sensor);

          liveFireKeys.add(key);

          _fireAlertStartTimes.putIfAbsent(
            key,
                () => DateTime.now(),
          );
        }
      }
    }

    _fireAlertStartTimes.removeWhere(
          (key, _) =>
      !liveFireKeys.contains(key),
    );
  }

  bool _wasFireAlertActive = false;

  // ==========================================================
  // BUILD
  // ==========================================================

  @override
  Widget build(
      BuildContext context,
      ) {
    final fireAlert =
        _anyFireAnywhere;

    if (fireAlert &&
        !_wasFireAlertActive) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) {
        if (!mounted) return;

        _setupAlertFloorFocusNodes();
        if (_fireFloors.isNotEmpty) {
          _requestAlertFloorFocus(
            _selectedAlertFloorIndex.clamp(
              0,
              _fireFloors.length - 1,
            ),
          );
        }

        _requestAlertCardFocus(0);
      });
    }

    _wasFireAlertActive = fireAlert;

    return Scaffold(
      backgroundColor:
      AppTheme.background,
      body: SafeArea(
        child: fireAlert
            ? _buildFireAlertDashboard()
            : NormalDashboardView(
          topStatusBar:
          _buildTopStatusBar(),
          leftPanel:
          _buildLeftPanel(),
          floorBody:
          _buildFloorBody(),
          rightPanel:
          _buildRightPanel(),
          bottomSummary:
          _buildBottomSummary(),
          emptyState:
          _buildEmptyState(),
          hasFloors:
          _store.history.isNotEmpty,
        ),
      ),
    );
  }

  // ==========================================================
  // TOP STATUS BAR
  // ==========================================================

  String _two(int n) =>
      n.toString().padLeft(2, '0');

  Widget _buildTopStatusBar({
    bool alertMode = false,
  }) {
    final isFire =
        alertMode || _anyFireAnywhere;

    return Container(
      height: 56,
      padding:
      const EdgeInsets.symmetric(
        horizontal: 14,
      ),
      decoration: BoxDecoration(
        color: isFire ? const Color(0xFF2A0606) : AppTheme.card,
        border: Border(
          bottom: BorderSide(
            color: AppTheme.divider,
          ),
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Logo - left side
          Align(
            alignment: Alignment.centerLeft,
            child: Image.asset(
              AppSettings.darkModeEnabled
                  ? 'assets/images/white logo.png'
                  : 'assets/images/black logo.png',
              width: 80,
              height: 80,
              fit: BoxFit.contain,
            ),
          ),

          // Normal / Fire Alert - CENTER
          Center(
            child: Text(
              isFire ? 'Fire Alert' : 'Normal',
              style: TextStyle(
                color: isFire
                    ? Colors.redAccent
                    : Colors.greenAccent,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          // Right side controls
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Live clock -- shown on both Normal and Fire Alert
                // screens (previously only appeared in the Normal
                // dashboard's bottom summary bar).
                SizedBox(
                  width: 75,
                  child: Text(
                    '${_two(_now.hour)}:'
                        '${_two(_now.minute)}:'
                        '${_two(_now.second)}\n'
                        '${_two(_now.day)}/'
                        '${_two(_now.month)}/'
                        '${_now.year}',
                    textAlign:
                    TextAlign.right,
                    style: TextStyle(
                      color: isFire
                          ? Colors.white70
                          : AppTheme
                          .textSecondary,
                      fontSize: 12,
                      height: 1.2,
                      fontWeight:
                      FontWeight.w600,
                    ),
                  ),
                ),

                const SizedBox(width: 10),

                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: widget.manager.connectionStatus ==
                          'Connected'
                          ? Colors.tealAccent
                          : Colors.orange,
                    ),
                  ),
                  child: Text(
                    widget.manager.connectionStatus,
                    style: TextStyle(
                      color: widget.manager.connectionStatus ==
                          'Connected'
                          ? Colors.tealAccent
                          : Colors.orange,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),

                const SizedBox(width: 8),

                if (AppSettings.sirenEnabled)
                  IconButton(
                    icon: Icon(
                      _isMuted
                          ? Icons.volume_off
                          : Icons.volume_up,
                      color: AppTheme.textSecondary,
                    ),
                    tooltip: _isMuted
                        ? 'Unmute alarm'
                        : 'Mute alarm',
                    onPressed: _toggleMute,
                  ),

                const SizedBox(width: 4),

                // Back to the main menu -- lets the user add another
                // floor image (Configuration) or scan for a new device
                // (Devices) without leaving the app. The Dashboard is the
                // launch screen once a config exists, so it has no back
                // button of its own; this is the way back to that menu.
                IconButton(
                  icon: Icon(
                    Icons.menu,
                    color: AppTheme.textSecondary,
                  ),
                  tooltip: 'Menu',
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            HomeScreen(manager: widget.manager),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // FLOOR TAB BAR
  // ==========================================================

  Widget _buildFloorTabBar() {
    if (_store.history.isEmpty) {
      return const SizedBox.shrink();
    }

    _setupFocusNodes();

    return Container(
      constraints:
      const BoxConstraints(
        maxHeight: 240,
      ),
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(
            color: AppTheme.divider,
          ),
          bottom: BorderSide(
            color: AppTheme.divider,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.stretch,
        children: [
          // ==================================================
          // FLOOR HEADER
          // ==================================================

          Focus(
            focusNode:
            _floorHeaderFocusNode,
            onFocusChange: (_) {
              if (mounted) {
                setState(() {});
              }
            },
            onKeyEvent:
                (node, event) {
              if (event
              is! KeyDownEvent) {
                return KeyEventResult
                    .ignored;
              }

              final key =
                  event.logicalKey;

              if (key ==
                  LogicalKeyboardKey
                      .arrowDown &&
                  _store.history
                      .isNotEmpty) {
                _requestFloorFocus(
                  _focusedFloorIndex,
                );

                return KeyEventResult
                    .handled;
              }

              return KeyEventResult
                  .ignored;
            },
            child: Container(
              height: 42,
              padding:
              const EdgeInsets.symmetric(
                horizontal: 12,
              ),
              alignment:
              Alignment.centerLeft,
              child: Row(
                children: [
                  Icon(
                    Icons.layers,
                    size: 16,
                    color:
                    AppTheme.textPrimary,
                  ),
                  const SizedBox(
                    width: 7,
                  ),
                  Text(
                    'Floor',
                    style: TextStyle(
                      color:
                      AppTheme.textPrimary,
                      fontSize: 13,
                      fontWeight:
                      FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ==================================================
          // FLOOR LIST
          // ==================================================

          Expanded(
            child:
            SingleChildScrollView(
              controller:
              _floorTabScrollController,
              child: Column(
                children: List.generate(
                  _store.history.length,
                      (index) {
                    final floor =
                    _store.history[
                    index];

                    final isSelected =
                        index ==
                            _selectedFloorIndex;

                    final isFocused =
                        _focusedFloorIndex ==
                            index &&
                            !_focusIsOnDeviceList;

                    return Focus(
                      focusNode:
                      _floorFocusNodes[
                      index],
                      onFocusChange:
                          (focused) {
                        if (!mounted)
                          return;

                        if (focused) {
                          setState(() {
                            _focusedFloorIndex =
                                index;

                            _focusIsOnDeviceList =
                            false;
                          });

                          _scrollFloorIntoView(
                            index,
                          );
                        }
                      },
                      onKeyEvent:
                          (node, event) {
                        if (event
                        is! KeyDownEvent) {
                          return KeyEventResult
                              .ignored;
                        }

                        final key =
                            event.logicalKey;

                        // ====================================
                        // OK / ENTER
                        // ====================================

                        if (key ==
                            LogicalKeyboardKey
                                .enter ||
                            key ==
                                LogicalKeyboardKey
                                    .select ||
                            key ==
                                LogicalKeyboardKey
                                    .numpadEnter) {
                          _selectFloor(index);

                          return KeyEventResult
                              .handled;
                        }

                        // ====================================
                        // DOWN
                        // ====================================

                        if (key ==
                            LogicalKeyboardKey
                                .arrowDown) {
                          if (index <
                              _store.history
                                  .length -
                                  1) {
                            _requestFloorFocus(
                              index + 1,
                            );
                          } else {
                            // Last floor -> first device
                            _requestFirstDevice();
                          }

                          return KeyEventResult
                              .handled;
                        }

                        // ====================================
                        // UP
                        // ====================================

                        if (key ==
                            LogicalKeyboardKey
                                .arrowUp) {
                          if (index > 0) {
                            _requestFloorFocus(
                              index - 1,
                            );
                          } else {
                            _floorHeaderFocusNode
                                .requestFocus();
                          }

                          return KeyEventResult
                              .handled;
                        }

                        return KeyEventResult
                            .ignored;
                      },
                      child:
                      InkWell(
                        onTap: () {
                          _selectFloor(
                            index,
                          );
                        },
                        child:
                        AnimatedContainer(
                          duration:
                          const Duration(
                            milliseconds: 120,
                          ),
                          height: 40,
                          padding:
                          const EdgeInsets
                              .symmetric(
                            horizontal: 12,
                          ),
                          decoration:
                          BoxDecoration(
                            color:
                            isSelected
                                ? AppTheme
                                .textPrimary
                                .withOpacity(
                              0.08,
                            )
                                : isFocused
                                ? Colors
                                .tealAccent
                                .withOpacity(
                              0.08,
                            )
                                : Colors
                                .transparent,
                            border:
                            Border(
                              left:
                              BorderSide(
                                color:
                                isFocused
                                    ? Colors
                                    .tealAccent
                                    : isSelected
                                    ? Colors
                                    .tealAccent
                                    : Colors
                                    .transparent,
                                width: 3,
                              ),
                            ),
                          ),
                          alignment:
                          Alignment
                              .centerLeft,
                          child:
                          Text(
                            floor
                                .floorLabel,
                            style:
                            TextStyle(
                              color: isFocused
                                  ? Colors
                                  .tealAccent
                                  : isSelected
                                  ? AppTheme
                                  .textPrimary
                                  : AppTheme
                                  .textSecondary,
                              fontWeight:
                              isSelected ||
                                  isFocused
                                  ? FontWeight
                                  .bold
                                  : FontWeight
                                  .normal,
                              fontSize:
                              13,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // SELECT FLOOR
  // ==========================================================

  void _selectFloor(int index) {
    if (index < 0 ||
        index >= _store.history.length) {
      return;
    }

    setState(() {
      _selectedFloorIndex = index;

      _selectedSensor = null;

      _focusedFloorIndex = index;

      _focusedDeviceIndex = 0;

      _focusIsOnDeviceList = false;
    });

    _setupFocusNodes();

    _requestFloorFocus(index);

    // Scroll device list to top
    if (_deviceScrollController
        .hasClients) {
      _deviceScrollController.jumpTo(0);
    }
  }

  // ==========================================================
  // FIRST DEVICE
  // ==========================================================

  void _requestFirstDevice() {
    final floor = _currentFloor;

    if (floor == null ||
        floor.sensors.isEmpty) {
      return;
    }

    _setupFocusNodes();

    _requestDeviceFocus(0);
  }

  // ==========================================================
  // DEVICE LIST
  // ==========================================================

  Widget _buildDeviceList(
      SiteImageConfig floor,
      ) {
    if (floor.sensors.isEmpty) {
      return Padding(
        padding:
        const EdgeInsets.all(12),
        child: Text(
          'No sensors placed on this floor yet',
          style: TextStyle(
            color:
            AppTheme.textSecondary,
            fontSize: 12,
          ),
        ),
      );
    }

    _setupFocusNodes();

    return ListView.builder(
      controller:
      _deviceScrollController,
      itemCount:
      floor.sensors.length,
      itemBuilder:
          (context, index) {
        final sensor =
        floor.sensors[index];

        final status =
        _statusFor(sensor);

        final isSelected =
            _selectedSensor ==
                sensor;

        final isFocused =
            _focusIsOnDeviceList &&
                _focusedDeviceIndex ==
                    index;

        return Focus(
          focusNode:
          _deviceFocusNodes[
          index],
          onFocusChange:
              (focused) {
            if (!mounted) return;

            if (focused) {
              setState(() {
                _focusedDeviceIndex =
                    index;

                _focusIsOnDeviceList =
                true;
              });

              _scrollDeviceIntoView(
                index,
              );
            }
          },
          onKeyEvent:
              (node, event) {
            if (event
            is! KeyDownEvent) {
              return KeyEventResult
                  .ignored;
            }

            final key =
                event.logicalKey;

            // ==============================================
            // OK / ENTER
            // ==============================================

            if (key ==
                LogicalKeyboardKey
                    .enter ||
                key ==
                    LogicalKeyboardKey
                        .select ||
                key ==
                    LogicalKeyboardKey
                        .numpadEnter) {
              _selectDevice(
                sensor,
              );

              return KeyEventResult
                  .handled;
            }

            // ==============================================
            // UP
            // ==============================================

            if (key ==
                LogicalKeyboardKey
                    .arrowUp) {
              if (index > 0) {
                _requestDeviceFocus(
                  index - 1,
                );
              } else {
                // ==========================================
                // FIRST DEVICE -> FLOOR LIST
                // ==========================================

                _requestFloorFocus(
                  _selectedFloorIndex,
                );
              }

              return KeyEventResult
                  .handled;
            }

            // ==============================================
            // DOWN
            // ==============================================

            if (key ==
                LogicalKeyboardKey
                    .arrowDown) {
              if (index <
                  floor.sensors
                      .length -
                      1) {
                _requestDeviceFocus(
                  index + 1,
                );
              }

              return KeyEventResult
                  .handled;
            }

            return KeyEventResult
                .ignored;
          },
          child: InkWell(
            onTap: () {
              _selectDevice(
                sensor,
              );
            },
            child: AnimatedContainer(
              duration:
              const Duration(
                milliseconds: 120,
              ),
              padding:
              const EdgeInsets
                  .symmetric(
                horizontal: 8,
                vertical: 5,
              ),
              decoration:
              BoxDecoration(
                color: isSelected
                    ? AppTheme
                    .textPrimary
                    .withOpacity(
                  0.06,
                )
                    : isFocused
                    ? Colors
                    .tealAccent
                    .withOpacity(
                  0.08,
                )
                    : Colors
                    .transparent,
                border:
                Border(
                  left: BorderSide(
                    color: isFocused
                        ? Colors
                        .tealAccent
                        : isSelected
                        ? Colors
                        .tealAccent
                        : Colors
                        .transparent,
                    width: 3,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _iconFor(
                      sensor,
                      status,
                    ),
                    color:
                    _colorFor(
                      status,
                    ),
                    size: 18,
                  ),

                  const SizedBox(
                    width: 8,
                  ),

                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                      CrossAxisAlignment
                          .start,
                      children: [
                        Text(
                          sensor.name,
                          maxLines: 1,
                          overflow:
                          TextOverflow
                              .ellipsis,
                          style:
                          TextStyle(
                            color: isFocused
                                ? Colors
                                .tealAccent
                                : AppTheme
                                .textSecondary,
                            fontSize:
                            12,
                            fontWeight:
                            isFocused
                                ? FontWeight
                                .bold
                                : FontWeight
                                .normal,
                          ),
                        ),
                        const SizedBox(
                          height: 2,
                        ),
                        Text(
                          status.name,
                          style:
                          TextStyle(
                            color:
                            _colorFor(
                              status,
                            ).withOpacity(
                              0.9,
                            ),
                            fontSize:
                            10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _selectDevice(
      PlacedSensor sensor,
      ) {
    setState(() {
      _selectedSensor =
      _selectedSensor == sensor
          ? null
          : sensor;
    });
  }

  // ==========================================================
  // LEFT PANEL
  // ==========================================================

  Widget _buildLeftPanel() {
    final floor = _currentFloor;

    if (floor == null) {
      return const SizedBox(
        width: 0,
      );
    }

    final deviceIds =
    _floorDeviceIds(floor)
        .toList()
      ..sort();

    final devicesTotal =
        deviceIds.length;

    final devicesOnline =
    _floorDevicesOnline(floor);

    return Container(
      width: 205,
      color: AppTheme.panel,
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment
            .stretch,
        children: [
          // FLOOR LIST
          SizedBox(
            height: 240,
            child:
            _buildFloorTabBar(),
          ),

          Divider(
            color:
            AppTheme.divider,
            height: 1,
          ),

          // DEVICE TITLE
          Padding(
            padding:
            const EdgeInsets
                .fromLTRB(
              12,
              12,
              12,
              6,
            ),
            child: Text(
              '${floor.floorLabel} device',
              style: TextStyle(
                color:
                AppTheme.textPrimary,
                fontWeight:
                FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),

          // DEVICE LIST
          Expanded(
            child:
            _buildDeviceList(
              floor,
            ),
          ),

          Divider(
            color:
            AppTheme.divider,
            height: 1,
          ),

          Padding(
            padding:
            const EdgeInsets.all(
              12,
            ),
            child: Text(
              'Devices: '
                  '$devicesOnline/'
                  '$devicesTotal online',
              style: TextStyle(
                color:
                AppTheme.textSecondary,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // FLOOR IMAGE HEADER
  // ==========================================================

  Widget _buildFloorImageHeader() {
    final floor = _currentFloor;

    return Container(
      height: 42,
      padding:
      const EdgeInsets.symmetric(
        horizontal: 16,
      ),
      alignment:
      Alignment.centerLeft,
      decoration: BoxDecoration(
        color: AppTheme.card,
        border: Border(
          bottom: BorderSide(
            color: AppTheme.divider,
          ),
        ),
      ),
      child: Text(
        floor == null
            ? 'Floor image'
            : floor.floorLabel,
        style: TextStyle(
          color:
          AppTheme.textPrimary,
          fontSize: 13,
          fontWeight:
          FontWeight.bold,
        ),
      ),
    );
  }

  // ==========================================================
  // RIGHT PANEL
  // ==========================================================

  Widget _buildRightPanel() {
    final offlineIds =
    ModbusRtu.slaveIds
        .where(
          (id) =>
          widget.manager.isSlaveOffline(id),
    )
        .toList()
      ..sort();

    final floorsWithOfflineDevices =
    _store.history.where(
          (floor) {
        return floor.sensors.any(
              (sensor) =>
              widget.manager.isSlaveOffline(
                sensor.slaveId,
              ),
        );
      },
    ).toList();

    return Container(
      width: 160,
      color: AppTheme.panel,
      padding: const EdgeInsets.fromLTRB(
        14,
        14,
        10,
        10,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: [
            // ==========================================
            // STATUS
            // ==========================================

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
              '$_globalDevicesOnline/'
                  '$_globalDevicesTotal',
            ),

            const SizedBox(height: 8),

            _sideStat(
              'Sensor',
              '$_globalSensorsOnline/'
                  '$_globalSensorsTotal',
            ),

            const SizedBox(height: 16),

            // ==========================================
            // OFFLINE DEVICE
            // ==========================================

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
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 11,
                ),
              )
            else ...[
              ...offlineIds.map(
                    (id) => Padding(
                  padding:
                  const EdgeInsets.symmetric(
                    vertical: 2,
                  ),
                  child: Text(
                    'Device $id',
                    style: TextStyle(
                      color:
                      AppTheme.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),

              // ========================================
              // FLOOR AFFECTED
              // ONLY SHOW WHEN OFFLINE EXISTS
              // ========================================

              if (floorsWithOfflineDevices
                  .isNotEmpty) ...[
                const SizedBox(height: 14),

                Text(
                  'Floors affected',
                  style: TextStyle(
                    color:
                    AppTheme.textSecondary,
                    fontSize: 12,
                    fontWeight:
                    FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 6),

                ...floorsWithOfflineDevices.map(
                      (floor) => Padding(
                    padding:
                    const EdgeInsets.symmetric(
                      vertical: 2,
                    ),
                    child: Text(
                      floor.floorLabel,
                      style: TextStyle(
                        color:
                        AppTheme.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _sideStat(
      String label,
      String value,
      ) {
    return Row(
      mainAxisAlignment:
      MainAxisAlignment
          .spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color:
            AppTheme.textSecondary,
            fontSize: 12,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color:
            AppTheme.textPrimary,
            fontSize: 12,
            fontWeight:
            FontWeight.bold,
          ),
        ),
      ],
    );
  }

  // ==========================================================
  // BOTTOM SUMMARY
  // ==========================================================

  Widget _buildBottomSummary() {
    final floor = _currentFloor;

    if (floor == null) {
      return const SizedBox.shrink();
    }

    final devicesTotal =
        _floorDeviceIds(floor)
            .length;

    final devicesOnline =
    _floorDevicesOnline(floor);

    final sensorsTotal =
        floor.sensors.length;

    final sensorsOnline =
    _floorSensorsOnline(floor);

    final sensorsOffline =
        sensorsTotal -
            sensorsOnline;

    return Container(
      height: 48,
      width: double.infinity,
      padding:
      const EdgeInsets.symmetric(
        horizontal: 16,
      ),
      decoration: BoxDecoration(
        color: AppTheme.card,
        border: Border(
          top: BorderSide(
            color: AppTheme.divider,
          ),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              floor.floorLabel,
              style: const TextStyle(
                color:
                Colors.tealAccent,
                fontWeight:
                FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),

          VerticalDivider(
            color:
            AppTheme.divider,
            width: 1,
          ),

          Expanded(
            child: Text(
              'Total device: '
                  '$devicesTotal',
              style: TextStyle(
                color: AppTheme
                    .textSecondary,
                fontSize: 12,
              ),
            ),
          ),

          Expanded(
            child: Text(
              'Total sensor: '
                  '$sensorsOnline/'
                  '$sensorsTotal',
              style: TextStyle(
                color: AppTheme
                    .textSecondary,
                fontSize: 12,
              ),
            ),
          ),

          Expanded(
            child: Text(
              'Online: '
                  '$devicesOnline',
              style:
              const TextStyle(
                color:
                Colors.greenAccent,
                fontSize: 12,
              ),
            ),
          ),

          Expanded(
            child: Text(
              'Offline: '
                  '$sensorsOffline',
              style:
              const TextStyle(
                color:
                Colors.orangeAccent,
                fontSize: 12,
              ),
            ),
          ),

          const Spacer(),

          SizedBox(
            width: 75,
            child: Text(
              '${_two(_now.hour)}:'
                  '${_two(_now.minute)}:'
                  '${_two(_now.second)}\n'
                  '${_two(_now.day)}/'
                  '${_two(_now.month)}/'
                  '${_now.year}',
              textAlign:
              TextAlign.right,
              style: TextStyle(
                color: AppTheme
                    .textSecondary,
                fontSize: 12,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // EMPTY STATE
  // ==========================================================

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize:
        MainAxisSize.min,
        children: const [
          Icon(
            Icons.image_outlined,
            size: 64,
            color: Colors.grey,
          ),
          SizedBox(
            height: 12,
          ),
          Text(
            'No floor plan configured yet',
            style: TextStyle(
              color: Colors.grey,
              fontSize: 16,
            ),
          ),
          SizedBox(
            height: 4,
          ),
          Text(
            'Load one from the Configuration screen',
            style: TextStyle(
              color: Colors.grey,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // FLOOR IMAGE
  // ==========================================================

  final Map<String, Size>
  _sizeCache = {};

  final Map<String, Widget>
  _svgCache = {};

  Widget _svgFor(String path) {
    return _svgCache.putIfAbsent(
      path,
          () => SvgPicture.file(
        File(path),
        fit: BoxFit.fill,
      ),
    );
  }

  Future<Size> _resolveImageSize(
      String path,
      ) async {
    final cached =
    _sizeCache[path];

    if (cached != null) {
      return cached;
    }

    final info =
    await vg.loadPicture(
      SvgFileLoader(
        File(path),
      ),
      null,
    );

    info.picture.dispose();

    _sizeCache[path] =
        info.size;

    return info.size;
  }

  Widget _buildFloorBody({
    SiteImageConfig?
    floorOverride,
    List<PlacedSensor>?
    sensorsOverride,
  }) {
    final floor =
        floorOverride ??
            _currentFloor;

    if (floor == null) {
      return _buildEmptyState();
    }

    final cachedSize =
    _sizeCache[
    floor.imagePath];

    if (cachedSize != null) {
      return _buildFloorImage(
        floor,
        cachedSize,
        sensorsOverride:
        sensorsOverride,
      );
    }

    return FutureBuilder<Size>(
      future:
      _resolveImageSize(
        floor.imagePath,
      ),
      builder:
          (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
            child:
            CircularProgressIndicator(),
          );
        }

        return _buildFloorImage(
          floor,
          snapshot.data!,
          sensorsOverride:
          sensorsOverride,
        );
      },
    );
  }

  Widget _buildFloorImage(
      SiteImageConfig floor,
      Size imgSize, {
        List<PlacedSensor>?
        sensorsOverride,
      }) {
    final aspectRatio =
        imgSize.width /
            imgSize.height;

    // Fire Alert dashboard passes only the currently-firing sensors here
    // so the floor map matches the alert-card row below it (alerting
    // devices only). The normal dashboard leaves this null and still
    // shows every placed sensor on the floor.
    final pinsToShow =
        sensorsOverride ??
            floor.sensors;

    return Padding(
      padding:
      const EdgeInsets.all(
        16,
      ),
      child: Center(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: AspectRatio(
            aspectRatio:
            aspectRatio,
            child: LayoutBuilder(
              builder:
                  (context,
                  constraints) {
                return Container(
                  decoration:
                  BoxDecoration(
                    color: AppTheme
                        .textPrimary,
                    borderRadius:
                    BorderRadius
                        .circular(
                      8,
                    ),
                  ),
                  child:
                  ClipRRect(
                    borderRadius:
                    BorderRadius
                        .circular(
                      8,
                    ),
                    child:
                    Stack(
                      fit: StackFit
                          .expand,
                      children: [
                        _svgFor(
                          floor.imagePath,
                        ),

                        for (final sensor
                        in pinsToShow)
                          _buildPin(
                            sensor,
                            constraints
                                .biggest,
                          ),
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

  // ==========================================================
  // SENSOR PIN
  // ==========================================================

  Widget _buildPin(
      PlacedSensor sensor,
      Size canvasSize,
      ) {
    final pinSize =
        AppSettings.pinSize;

    final iconSize =
        pinSize * 0.5;

    final rippleBoxSize =
        pinSize * 3;

    final status =
    _statusFor(sensor);

    final color =
    _colorFor(status);

    final isFire =
        status ==
            _PinLiveStatus.fire;

    final isSelected =
        _selectedSensor ==
            sensor;

    final isFocused =
        _focusedSensor ==
            sensor;

    return Positioned(
      key: ValueKey(
        'pin_${_pinKey(sensor)}',
      ),
      left:
      sensor.xFraction *
          canvasSize.width -
          rippleBoxSize / 2,
      top:
      sensor.yFraction *
          canvasSize.height -
          rippleBoxSize / 2,
      width:
      rippleBoxSize,
      height:
      rippleBoxSize,
      child: Stack(
        alignment:
        Alignment.center,
        children: [
          if (isFire)
            IgnorePointer(
              child:
              AnimatedBuilder(
                animation:
                _rippleController,
                builder:
                    (context, _) {
                  return CustomPaint(
                    size: Size(
                      rippleBoxSize,
                      rippleBoxSize,
                    ),
                    painter:
                    _FireRipplePainter(
                      progress:
                      _rippleController
                          .value,
                      color:
                      Colors.redAccent,
                    ),
                  );
                },
              ),
            ),

          Focus(
            focusNode:
            _focusNodeFor(
              sensor,
            ),
            onFocusChange:
                (focused) {
              if (!mounted) {
                return;
              }

              setState(() {
                _focusedSensor =
                focused
                    ? sensor
                    : null;
              });
            },
            onKeyEvent:
                (node, event) {
              if (event
              is! KeyDownEvent) {
                return KeyEventResult
                    .ignored;
              }

              final key =
                  event.logicalKey;

              if (key ==
                  LogicalKeyboardKey
                      .enter ||
                  key ==
                      LogicalKeyboardKey
                          .select ||
                  key ==
                      LogicalKeyboardKey
                          .numpadEnter) {
                _toggleSensorSelection(
                  sensor,
                );

                return KeyEventResult
                    .handled;
              }

              return KeyEventResult
                  .ignored;
            },
            child:
            GestureDetector(
              onTap: () =>
                  _toggleSensorSelection(
                    sensor,
                  ),
              child:
              MouseRegion(
                cursor:
                SystemMouseCursors
                    .click,
                child:
                Tooltip(
                  message:
                  '${sensor.name} '
                      '(${sensor.zoneLabel})\n'
                      '${sensor.location}\n'
                      '${status.name}',
                  child:
                  AnimatedContainer(
                    duration:
                    const Duration(
                      milliseconds:
                      300,
                    ),
                    width:
                    pinSize,
                    height:
                    pinSize,
                    decoration:
                    BoxDecoration(
                      shape:
                      BoxShape.circle,
                      color:
                      color,
                      border:
                      isSelected
                          ? Border.all(
                        color:
                        AppTheme
                            .textPrimary,
                        width: 3,
                      )
                          : isFocused
                          ? Border.all(
                        color:
                        Colors
                            .tealAccent,
                        width: 2,
                      )
                          : null,
                      boxShadow: [
                        if (isFire)
                          BoxShadow(
                            color: Colors
                                .red
                                .withOpacity(
                              0.6,
                            ),
                            blurRadius:
                            16,
                            spreadRadius:
                            4,
                          ),
                        if (isFocused &&
                            !isSelected)
                          BoxShadow(
                            color: Colors
                                .tealAccent
                                .withOpacity(
                              0.5,
                            ),
                            blurRadius:
                            12,
                            spreadRadius:
                            2,
                          ),
                      ],
                    ),
                    child:
                    Icon(
                      _iconFor(
                        sensor,
                        status,
                      ),
                      color:
                      AppTheme
                          .textPrimary,
                      size:
                      iconSize,
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

  // ==========================================================
  // FIRE ALERT DASHBOARD
  // ==========================================================

  /// Lower number = higher priority (matches the Devices screen, where
  /// "Priority 1" is set as the most urgent). A device with no priority
  /// assigned is treated as lowest priority, so any prioritized alert
  /// always outranks it.
  int _priorityRank(PlacedSensor sensor) {
    final p =
    ModbusRtu.priorityForSlave(
      sensor.slaveId,
    );
    return p ?? (1 << 30);
  }

  /// The currently-firing sensor on [floor] with the best (numerically
  /// lowest) priority, or null if nothing on this floor is firing.
  PlacedSensor?
  _bestPrioritySensorForFloor(
      SiteImageConfig floor,
      ) {
    PlacedSensor? best;

    for (final sensor
    in floor.sensors) {
      if (_statusFor(sensor) !=
          _PinLiveStatus.fire) {
        continue;
      }

      if (best == null ||
          _priorityRank(sensor) <
              _priorityRank(best)) {
        best = sensor;
      }
    }

    return best;
  }

  List<SiteImageConfig>
  get _fireFloors {
    final floors =
        _store.history
            .where(
              (floor) =>
              floor.sensors.any(
                    (sensor) =>
                _statusFor(
                  sensor,
                ) ==
                    _PinLiveStatus
                        .fire,
              ),
        )
            .toList();

    // Show the floor with the highest-priority active fire first, so
    // it's the one auto-selected (index 0) when multiple floors are
    // alerting at once. A stable index tie-break keeps ordering
    // deterministic when priorities match (e.g. several un-prioritized
    // floors alerting together).
    final indexed =
    floors.asMap().entries.toList();

    indexed.sort((a, b) {
      final aBest =
      _bestPrioritySensorForFloor(
        a.value,
      );
      final bBest =
      _bestPrioritySensorForFloor(
        b.value,
      );
      final aRank = aBest != null
          ? _priorityRank(aBest)
          : (1 << 30);
      final bRank = bBest != null
          ? _priorityRank(bBest)
          : (1 << 30);

      final cmp =
      aRank.compareTo(bRank);
      if (cmp != 0) return cmp;

      return a.key.compareTo(b.key);
    });

    return indexed
        .map((e) => e.value)
        .toList();
  }

  SiteImageConfig?
  get _selectedAlertFloor {
    final floors =
        _fireFloors;

    if (floors.isEmpty) {
      return null;
    }

    final index =
    _selectedAlertFloorIndex
        .clamp(
      0,
      floors.length - 1,
    );

    return floors[index];
  }

  /// Every sensor on [floor] that is currently on fire, sorted by
  /// priority first (Priority 1 before Priority 2 before unprioritized),
  /// then by how long each has been alerting (earliest first) -- so
  /// when one device has several zones (e.g. an MLP's 4 input
  /// registers) that trip at different times, every active one is
  /// listed with its own time, not just a single representative sensor.
  List<PlacedSensor>
  _firingSensorsForFloor(
      SiteImageConfig floor,
      ) {
    final firing = floor.sensors
        .where(
          (s) =>
      _statusFor(s) ==
          _PinLiveStatus.fire,
    )
        .toList();

    firing.sort((a, b) {
      final rankCmp =
      _priorityRank(a)
          .compareTo(
        _priorityRank(b),
      );
      if (rankCmp != 0) {
        return rankCmp;
      }

      final aStart =
      _fireAlertStartTimes[
      _pinKey(a)];
      final bStart =
      _fireAlertStartTimes[
      _pinKey(b)];

      if (aStart == null &&
          bStart == null) {
        return 0;
      }
      if (aStart == null) return 1;
      if (bStart == null) return -1;

      return aStart.compareTo(
        bStart,
      );
    });

    return firing;
  }

  Widget _buildFireAlertDashboard() {
    final fireFloors =
        _fireFloors;

    if (fireFloors.isEmpty) {
      return const SizedBox
          .shrink();
    }

    final selectedIndex = _selectedAlertFloorIndex.clamp(
      0,
      fireFloors.length - 1,
    );
    final selectedFloor = fireFloors[selectedIndex];

    final firingSensors =
    _firingSensorsForFloor(
      selectedFloor,
    );

    return FireAlertDashboardView(
      topStatusBar:
      _buildTopStatusBar(
        alertMode: true,
      ),
      fireFloors:
      fireFloors,
      selectedFloorIndex: selectedIndex,
      focusedFloorIndex: _focusedAlertFloorIndex,
      floorFocusNodes: _alertFloorFocusNodes,
      onFloorFocused: _onAlertFloorFocused,
      onFloorMove: _moveAlertFloorFocus,
      onFloorSelected: _selectAlertFloor,
      selectedFloor:
      selectedFloor,
      floorBody:
      _buildFloorBody(
        floorOverride:
        selectedFloor,
        sensorsOverride:
        firingSensors,
      ),
      alertDeviceDetails:
      _buildAlertDeviceDetails(
        firingSensors,
        selectedFloor,
      ),
    );
  }

  Widget _buildAlertDeviceDetails(
      List<PlacedSensor> sensors,
      SiteImageConfig floor,
      ) {
    // Keep the focus-node pool in sync with how many alert cards are
    // currently shown, so remote left/right can step through exactly
    // these cards.
    WidgetsBinding.instance
        .addPostFrameCallback((_) {
      if (!mounted) return;
      _setupAlertCardFocusNodes(
        sensors.length,
      );
    });

    return Container(
      height: 96,
      width: double.infinity,
      padding:
      const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 8,
      ),
      decoration:
      const BoxDecoration(
        color: Color(0xFF200404),
        border: Border(
          top: BorderSide(
            color:
            Colors.redAccent,
          ),
        ),
      ),
      child: sensors.isEmpty
          ? Center(
        child: Text(
          'Fire device information unavailable',
          style: TextStyle(
            color: AppTheme
                .textSecondary,
            fontSize: 12,
          ),
        ),
      )
          : Scrollbar(
        controller:
        _alertCardScrollController,
        thumbVisibility: true,
        trackVisibility: true,
        child: ListView.separated(
          controller:
          _alertCardScrollController,
          scrollDirection:
          Axis.horizontal,
          itemCount:
          sensors.length,
          separatorBuilder:
              (_, __) =>
          const SizedBox(
            width: 10,
          ),
          itemBuilder:
              (context, i) =>
              _alertDeviceCard(
                sensors[i],
                i,
                sensors.length,
              ),
        ),
      ),
    );
  }

  Widget _alertDeviceCard(
      PlacedSensor sensor,
      int index,
      int cardCount,
      ) {
    final isSelected =
        _selectedSensor == sensor;

    final focusNode =
    index <
        _alertCardFocusNodes.length
        ? _alertCardFocusNodes[index]
        : null;

    return Focus(
      focusNode: focusNode,
      onFocusChange: (focused) {
        if (focused) {
          _focusedAlertCardIndex =
              index;
        }
      },
      onKeyEvent: (node, event) {
        if (event
        is! KeyDownEvent) {
          return KeyEventResult
              .ignored;
        }

        final key =
            event.logicalKey;

        // Remote left/right steps between alert cards.
        if (key ==
            LogicalKeyboardKey
                .arrowRight) {
          if (index <
              cardCount - 1) {
            _requestAlertCardFocus(
              index + 1,
            );
          }
          return KeyEventResult
              .handled;
        }

        if (key ==
            LogicalKeyboardKey
                .arrowLeft) {
          if (index > 0) {
            _requestAlertCardFocus(
              index - 1,
            );
          }
          return KeyEventResult
              .handled;
        }

        if (key ==
            LogicalKeyboardKey
                .enter ||
            key ==
                LogicalKeyboardKey
                    .select ||
            key ==
                LogicalKeyboardKey
                    .numpadEnter) {
          setState(() {
            _selectedSensor =
            isSelected
                ? null
                : sensor;
          });
          return KeyEventResult
              .handled;
        }

        return KeyEventResult
            .ignored;
      },
      child: Builder(
        builder: (context) {
          final hasFocus =
              Focus.of(context)
                  .hasFocus;

          return GestureDetector(
            onTap: () {
              Focus.of(context)
                  .requestFocus();

              setState(() {
                _selectedSensor =
                isSelected
                    ? null
                    : sensor;
              });
            },
            child: Container(
              width: 420,
              padding:
              const EdgeInsets
                  .symmetric(
                horizontal: 14,
                vertical: 8,
              ),
              decoration:
              BoxDecoration(
                color: isSelected
                    ? const Color(
                    0xFF3A0A0A)
                    : Colors
                    .transparent,
                border: Border.all(
                  color: hasFocus
                      ? Colors
                      .white
                      : isSelected
                      ? Colors
                      .redAccent
                      : AppTheme
                      .divider,
                  width: hasFocus
                      ? 2
                      : 1,
                ),
                borderRadius:
                BorderRadius
                    .circular(8),
              ),
              child: Row(
                crossAxisAlignment:
                CrossAxisAlignment
                    .center,
                children: [
                  const Icon(
                    Icons
                        .local_fire_department,
                    color: Colors
                        .redAccent,
                    size: 26,
                  ),

                  const SizedBox(
                    width: 10,
                  ),

                  Expanded(
                    child:
                    _alertDetailText(
                      'Device',
                      sensor.name,
                    ),
                  ),

                  Expanded(
                    child:
                    _alertDetailText(
                      'Sensor',
                      sensor
                          .zoneLabel,
                    ),
                  ),

                  Expanded(
                    child:
                    _alertDetailText(
                      'Location',
                      sensor
                          .location,
                    ),
                  ),

                  Expanded(
                    child:
                    _alertDetailText(
                      'Time',
                      _formatAlertStartTime(
                        sensor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _formatAlertStartTime(
      PlacedSensor sensor,
      ) {
    final start =
    _fireAlertStartTimes[
    _pinKey(sensor)];

    if (start == null) {
      return '-';
    }

    return '${_two(start.hour)}:'
        '${_two(start.minute)}:'
        '${_two(start.second)}\n'
        '${_two(start.day)}/'
        '${_two(start.month)}/'
        '${start.year}';
  }

  Widget _alertDetailText(
      String label,
      String value,
      ) {
    return Padding(
      padding:
      const EdgeInsets.symmetric(
        horizontal: 8,
      ),
      child: Column(
        mainAxisAlignment:
        MainAxisAlignment
            .center,
        crossAxisAlignment:
        CrossAxisAlignment
            .start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: AppTheme
                  .textSecondary,
              fontSize: 10,
            ),
          ),
          const SizedBox(
            height: 3,
          ),
          Text(
            value.isEmpty
                ? '-'
                : value,
            maxLines: 2,
            overflow:
            TextOverflow.ellipsis,
            style: TextStyle(
              color: AppTheme
                  .textPrimary,
              fontSize: 12,
              fontWeight:
              FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statChip(
      String label, {
        Color? color,
      }) {
    return Container(
      margin:
      const EdgeInsets.symmetric(
        horizontal: 4,
      ),
      padding:
      const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: AppTheme
            .textPrimary
            .withOpacity(0.06),
        borderRadius:
        BorderRadius.circular(8),
        border: Border.all(
          color:
          color ??
              AppTheme.divider,
          width: 1,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color:
          color ??
              AppTheme.textSecondary,
          fontSize: 12,
          fontWeight:
          FontWeight.w600,
        ),
      ),
    );
  }
}