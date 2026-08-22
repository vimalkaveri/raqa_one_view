// ==========================
// File: screens/config/config_page.dart
//
// Configuration screen:
//   - Load a floor-plan image via the overflow menu. SVG only — other
//     formats are rejected by the file picker's extension filter.
//   - Only one image is "active" at a time, but every image loaded this
//     session is kept in history and can be swapped back in (see
//     ConfigurationStore / image_history_sheet.dart).
//   - Left rail: generic sensor-type icons (Signal / Fire / Speed /
//     Temperature). Drag one onto the floor plan to drop a pin there.
//   - On drop, the user picks which *scanned* device (ModbusRtu.slaveIds
//     — never the full 1-31 range) AND which zone on that device (a
//     device can have more than one physical sensor input — see
//     sensor_zones.dart) this pin represents, plus an editable
//     name/location/notes.
//   - Tap an existing pin to edit or remove it.
// ==========================

import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:vector_graphics/vector_graphics.dart';

import '../../services/config/configuration_store.dart';
import '../../services/config/placed_sensor.dart';
import '../../services/config/sensor_type.dart';
import '../../services/config/sensor_zones.dart';
import '../../services/rs485/modbus_rtu.dart';
import 'widgets/image_history_sheet.dart';
import 'widgets/sensor_edit_dialog.dart';

class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key});

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  final ConfigurationStore _store = ConfigurationStore.instance;
  final GlobalKey _canvasKey = GlobalKey();

  ////////////////////////////////////////////////////////////
  /// REMOTE (D-PAD) SENSOR PLACEMENT
  ///
  /// A TV remote has no pointer, so the drag-and-drop flow above isn't
  /// reachable from it. Instead: focus a rail icon and press Select to
  /// "arm" that sensor type, which shows a crosshair on the floor plan
  /// that the D-pad steers around; Select again drops the pin there
  /// (going through the same _onSensorDropped path the drag flow uses),
  /// Back/Escape cancels without placing. None of this touches the
  /// existing touch/mouse drag behaviour.
  ////////////////////////////////////////////////////////////

  final Map<SensorType, FocusNode> _railFocusNodes = {
    for (final type in SensorType.values)
      type: FocusNode(debugLabel: 'rail_${type.name}'),
  };
  final FocusNode _canvasFocusNode = FocusNode(debugLabel: 'canvas_crosshair');
  final Map<String, FocusNode> _pinFocusNodes = {};

  SensorType? _focusedRailType;
  String? _focusedPinKey;

  SensorType? _armedSensorType;
  Offset _crosshairFraction = const Offset(0.5, 0.5);

  static const double _crosshairStep = 0.02;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    for (final node in _railFocusNodes.values) {
      node.dispose();
    }
    for (final node in _pinFocusNodes.values) {
      node.dispose();
    }
    _canvasFocusNode.dispose();
    super.dispose();
  }

  void _onStoreChanged() {
    if (!mounted) return;
    _prunePinFocusNodes();
    setState(() {});
  }

  String _pinKey(PlacedSensor sensor) =>
      '${sensor.slaveId}_${sensor.zoneAddress}';

  FocusNode _pinFocusNodeFor(PlacedSensor sensor) {
    return _pinFocusNodes.putIfAbsent(
      _pinKey(sensor),
      () => FocusNode(debugLabel: 'pin_${_pinKey(sensor)}'),
    );
  }

  /// Drops focus nodes for pins no longer on the active image, so the map
  /// doesn't grow unbounded across a long session.
  void _prunePinFocusNodes() {
    final active = _store.active;
    final liveKeys = active == null
        ? const <String>{}
        : {for (final s in active.sensors) _pinKey(s)};

    final staleKeys =
        _pinFocusNodes.keys.where((k) => !liveKeys.contains(k)).toList();
    for (final key in staleKeys) {
      _pinFocusNodes.remove(key)?.dispose();
    }
  }

  ////////////////////////////////////////////////////////////
  /// CROSSHAIR ARM / MOVE / DROP
  ////////////////////////////////////////////////////////////

  void _armSensorType(SensorType type) {
    if (_store.active == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Load a floor plan before placing a sensor'),
        ),
      );
      return;
    }

    setState(() {
      _armedSensorType = type;
      _crosshairFraction = const Offset(0.5, 0.5);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _canvasFocusNode.requestFocus();
    });
  }

  void _disarmCrosshair() {
    final armedType = _armedSensorType;
    if (armedType == null) return;

    setState(() => _armedSensorType = null);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _railFocusNodes[armedType]?.requestFocus();
    });
  }

  void _moveCrosshair(double dx, double dy) {
    setState(() {
      _crosshairFraction = Offset(
        (_crosshairFraction.dx + dx).clamp(0.0, 1.0),
        (_crosshairFraction.dy + dy).clamp(0.0, 1.0),
      );
    });
  }

  Future<void> _dropArmedSensor() async {
    final type = _armedSensorType;
    if (type == null) return;

    final fraction = _crosshairFraction;
    // Disarm first (also returns focus to the rail) so the dialog opens
    // on top of a clean, non-armed canvas state.
    _disarmCrosshair();
    await _onSensorDropped(type, fraction);
  }

  KeyEventResult _handleCanvasKeyEvent(FocusNode node, KeyEvent event) {
    if (_armedSensorType == null) return KeyEventResult.ignored;
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.arrowLeft) {
      _moveCrosshair(-_crosshairStep, 0);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _moveCrosshair(_crosshairStep, 0);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _moveCrosshair(0, -_crosshairStep);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _moveCrosshair(0, _crosshairStep);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.numpadEnter) {
      _dropArmedSensor();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack) {
      _disarmCrosshair();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  ////////////////////////////////////////////////////////////
  /// SCANNED DEVICES / ZONE AVAILABILITY
  ////////////////////////////////////////////////////////////

  List<int> get _scannedSlaveIds {
    final ids = ModbusRtu.slaveIds
        .where((id) => ModbusRtu.slaveModelMap.containsKey(id))
        .toList()
      ..sort();
    return ids;
  }

  /// Zones on [slaveId] that don't have a pin on the active image yet.
  List<SensorZone> _availableZonesForSlave(int slaveId) {
    final type = ModbusRtu.slaveTypeMap[slaveId];
    if (type == null) return const [];

    final placedAddresses =
        _store.sensorsForSlave(slaveId).map((s) => s.zoneAddress).toSet();

    return zonesForDeviceType(type)
        .where((z) => !placedAddresses.contains(z.address))
        .toList();
  }

  /// Scanned devices that still have at least one un-pinned zone.
  List<int> get _placeableSlaveIds => _scannedSlaveIds
      .where((id) => _availableZonesForSlave(id).isNotEmpty)
      .toList();

  ////////////////////////////////////////////////////////////
  /// LOAD IMAGE (SVG only)
  ////////////////////////////////////////////////////////////

  Future<void> _loadImage() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['svg'],
    );

    if (files.isEmpty) return;
    final path = files.first.path;
    if (path == null) return;

    _store.addImage(path);
  }

  ////////////////////////////////////////////////////////////
  /// DROP HANDLING
  ////////////////////////////////////////////////////////////

  Future<void> _onSensorDropped(SensorType type, Offset fraction) async {
    if (_store.active == null) return;

    final available = _placeableSlaveIds;
    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Every scanned device already has all its zones pinned'),
        ),
      );
      return;
    }

    final result = await showAssignSensorDialog(
      context,
      type: type,
      xFraction: fraction.dx,
      yFraction: fraction.dy,
      availableSlaveIds: available,
      availableZonesForSlave: _availableZonesForSlave,
    );

    if (result != null) {
      _store.addOrUpdateSensor(result);
    }
  }

  Future<void> _onPinTapped(PlacedSensor sensor) async {
    final result = await showEditSensorDialog(
      context,
      sensor: sensor,
      onRemove: () => _store.removeSensor(sensor.slaveId, sensor.zoneAddress),
    );

    if (result != null) {
      _store.addOrUpdateSensor(result);
    }
  }

  ////////////////////////////////////////////////////////////
  /// MOVE HANDLING — repositioning an already-placed pin.
  /// Same (slaveId, zoneAddress) identity, just new coordinates, so this
  /// goes through addOrUpdateSensor's existing "update" path.
  ////////////////////////////////////////////////////////////

  void _onSensorMoved(PlacedSensor sensor, Offset fraction) {
    _store.addOrUpdateSensor(
      sensor.copyWith(xFraction: fraction.dx, yFraction: fraction.dy),
    );
  }

  ////////////////////////////////////////////////////////////
  /// UI
  ////////////////////////////////////////////////////////////

  @override
  Widget build(BuildContext context) {
    final activeConfig = _store.active;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F1F6),
      appBar: AppBar(
        title: const Text('Configuration'),
        backgroundColor: const Color(0xFFF4F1F6),
        foregroundColor: Colors.black87,
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'load') _loadImage();
              if (value == 'history') showImageHistorySheet(context);
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'load',
                child: ListTile(
                  leading: Icon(Icons.add_photo_alternate_outlined),
                  title: Text('Load Floor Plan (SVG)'),
                ),
              ),
              PopupMenuItem(
                value: 'history',
                child: ListTile(
                  leading: const Icon(Icons.history),
                  title: Text('Image History (${_store.history.length})'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: Row(
        children: [
          _buildSensorRail(),
          Expanded(
            child: activeConfig == null
                ? _buildEmptyState()
                : _buildImageCanvas(activeConfig.imagePath, activeConfig.sensors),
          ),
          _buildHintPanel(),
        ],
      ),
    );
  }

  ////////////////////////////////////////////////////////////
  /// LEFT RAIL — draggable generic sensor icons
  ////////////////////////////////////////////////////////////

  Widget _buildSensorRail() {
    return Container(
      width: 96,
      color: const Color(0xFFECE7EF),
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          for (final type in SensorType.values) ...[
            _buildDraggableIcon(type),
            const SizedBox(height: 20),
          ],
        ],
      ),
    );
  }

  Widget _buildDraggableIcon(SensorType type) {
    Widget circle({double radius = 32, double iconSize = 26, double opacity = 1}) {
      return Opacity(
        opacity: opacity,
        child: CircleAvatar(
          radius: radius,
          backgroundColor: Colors.white,
          child: Icon(type.icon, size: iconSize, color: Colors.black54),
        ),
      );
    }

    final isArmed = _armedSensorType == type;
    final isFocused = _focusedRailType == type;

    return Focus(
      focusNode: _railFocusNodes[type]!,
      onFocusChange: (focused) {
        if (!mounted) return;
        setState(() => _focusedRailType = focused ? type : null);
      },
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.numpadEnter) {
          _armSensorType(type);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Draggable<SensorType>(
          data: type,
          feedback: Material(
            color: Colors.transparent,
            child: circle(radius: 36, iconSize: 30),
          ),
          childWhenDragging: circle(opacity: 0.3),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: (isFocused || isArmed)
                  ? Border.all(
                      color: isArmed ? Colors.orange : Colors.teal,
                      width: 3,
                    )
                  : null,
            ),
            child: circle(),
          ),
        ),
      ),
    );
  }

  ////////////////////////////////////////////////////////////
  /// EMPTY STATE
  ////////////////////////////////////////////////////////////

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.image_outlined, size: 64, color: Colors.grey),
          const SizedBox(height: 12),
          const Text(
            'No floor plan loaded',
            style: TextStyle(color: Colors.grey, fontSize: 16),
          ),
          const SizedBox(height: 4),
          const Text(
            'SVG files only',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _loadImage,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('Load Floor Plan'),
          ),
        ],
      ),
    );
  }

  ////////////////////////////////////////////////////////////
  /// RIGHT PANEL — instructional hint
  ////////////////////////////////////////////////////////////

  Widget _buildHintPanel() {
    final armed = _armedSensorType;

    return Container(
      width: 260,
      color: const Color(0xFFECE7EF),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Text(
        armed == null
            ? 'Drag a sensor icon onto the layout, or tap an existing sensor '
                'to edit it.\n\nUsing a remote: focus a sensor icon and '
                'press Select to place it with the D-pad.'
            : 'Placing a ${armed.label} sensor.\n\nUse the D-pad to move '
                'the crosshair, Select to drop it here, Back to cancel.',
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.black54, fontSize: 15, height: 1.4),
      ),
    );
  }

  ////////////////////////////////////////////////////////////
  /// IMAGE CANVAS (drop target + rendered pins)
  ////////////////////////////////////////////////////////////

  Widget _buildImageCanvas(String imagePath, List<PlacedSensor> sensors) {
    return FutureBuilder<Size>(
      future: _resolveImageSize(imagePath),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final imgSize = snapshot.data!;
        final aspectRatio = imgSize.width / imgSize.height;

        return Padding(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: AspectRatio(
                aspectRatio: aspectRatio,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Object, not SensorType, because this canvas is a drop
                    // target for two different kinds of drag: a fresh
                    // SensorType dragged in from the left rail (new pin),
                    // and an existing PlacedSensor dragged from its current
                    // spot (move pin) — see _buildPin's Draggable below.
                    return DragTarget<Object>(
                      onWillAcceptWithDetails: (details) =>
                          details.data is SensorType ||
                          details.data is PlacedSensor,
                      onAcceptWithDetails: (details) {
                        final box = _canvasKey.currentContext!
                            .findRenderObject() as RenderBox;
                        final local = box.globalToLocal(details.offset);
                        final fraction = Offset(
                          (local.dx / constraints.maxWidth).clamp(0.0, 1.0),
                          (local.dy / constraints.maxHeight).clamp(0.0, 1.0),
                        );

                        final data = details.data;
                        if (data is SensorType) {
                          _onSensorDropped(data, fraction);
                        } else if (data is PlacedSensor) {
                          _onSensorMoved(data, fraction);
                        }
                      },
                      builder: (context, candidateData, rejectedData) {
                        return Focus(
                          focusNode: _canvasFocusNode,
                          onKeyEvent: _handleCanvasKeyEvent,
                          child: Container(
                            key: _canvasKey,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: candidateData.isNotEmpty
                                  ? Border.all(color: Colors.teal, width: 3)
                                  : null,
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  SvgPicture.file(
                                    File(imagePath),
                                    fit: BoxFit.fill,
                                  ),
                                  for (final sensor in sensors)
                                    _buildPin(sensor, constraints.biggest),
                                  if (_armedSensorType != null)
                                    _buildCrosshair(constraints.biggest),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
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

    Widget pinCircle({double opacity = 1, bool focused = false}) {
      return Opacity(
        opacity: opacity,
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: focused ? Border.all(color: Colors.teal, width: 3) : null,
          ),
          child: CircleAvatar(
            radius: pinSize / 2,
            backgroundColor: Colors.white.withOpacity(0.85),
            child: Icon(sensor.type.icon, color: sensor.type.color, size: 22),
          ),
        ),
      );
    }

    final isFocused = _focusedPinKey == _pinKey(sensor);

    return Positioned(
      key: ValueKey('pin_${_pinKey(sensor)}'),
      left: sensor.xFraction * canvasSize.width - pinSize / 2,
      top: sensor.yFraction * canvasSize.height - pinSize / 2,
      // Focus lets a remote reach an already-placed pin: Select opens the
      // same edit dialog a tap does. Draggable still handles touch/mouse
      // drag-to-move (handled by the DragTarget<Object> above, via
      // _onSensorMoved); a plain tap (no movement) falls through to the
      // GestureDetector to open the edit dialog — Draggable only claims
      // the gesture once real drag motion is detected.
      child: Focus(
        focusNode: _pinFocusNodeFor(sensor),
        onFocusChange: (focused) {
          if (!mounted) return;
          setState(() => _focusedPinKey = focused ? _pinKey(sensor) : null);
        },
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.select ||
              key == LogicalKeyboardKey.numpadEnter) {
            _onPinTapped(sensor);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Draggable<PlacedSensor>(
          data: sensor,
          feedback: Material(
            color: Colors.transparent,
            child: pinCircle(),
          ),
          childWhenDragging: pinCircle(opacity: 0.3),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => _onPinTapped(sensor),
              child: Tooltip(
                message:
                    '${sensor.name} (${sensor.zoneLabel})\n${sensor.location}',
                child: pinCircle(focused: isFocused),
              ),
            ),
          ),
        ),
      ),
    );
  }

  ////////////////////////////////////////////////////////////
  /// CROSSHAIR OVERLAY — shown while a sensor type is armed via remote.
  /// Purely visual/non-interactive (touch/mouse never target this); the
  /// canvas Focus wrapper is what actually steers it via the D-pad.
  ////////////////////////////////////////////////////////////

  Widget _buildCrosshair(Size canvasSize) {
    const size = 56.0;

    return Positioned(
      left: _crosshairFraction.dx * canvasSize.width - size / 2,
      top: _crosshairFraction.dy * canvasSize.height - size / 2,
      child: IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.orange.withOpacity(0.15),
            border: Border.all(color: Colors.orange, width: 3),
          ),
          child: Icon(
            _armedSensorType!.icon,
            color: Colors.orange,
            size: 24,
          ),
        ),
      ),
    );
  }

  ////////////////////////////////////////////////////////////
  /// SVG INTRINSIC SIZE (needed so pins/drops map to the correct spot
  /// regardless of how the file is scaled on screen)
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
}
