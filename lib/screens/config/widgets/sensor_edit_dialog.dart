// ==========================
// File: screens/config/widgets/sensor_edit_dialog.dart
//
// Two entry points:
//   - showAssignSensorDialog: used right after a sensor-type icon is
//     dropped onto the image. The user picks which scanned slave AND
//     which zone on that slave (a slave can have more than one physical
//     sensor zone — see sensor_zones.dart) this pin represents, then can
//     set name/location/notes.
//   - showEditSensorDialog: used when tapping an already-placed pin.
//     The slave/zone/type are fixed; name/location/notes stay editable,
//     plus a Remove option.
// ==========================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/config/placed_sensor.dart';
import '../../../services/config/sensor_type.dart';
import '../../../services/config/sensor_zones.dart';
import '../../../services/rs485/modbus_rtu.dart';

////////////////////////////////////////////////////////////
/// NEW PLACEMENT — pick which scanned device + zone this pin is
////////////////////////////////////////////////////////////

Future<PlacedSensor?> showAssignSensorDialog(
  BuildContext context, {
  required SensorType type,
  required double xFraction,
  required double yFraction,
  required List<int> availableSlaveIds,
  required List<SensorZone> Function(int slaveId) availableZonesForSlave,
}) {
  int? selectedSlaveId =
      availableSlaveIds.isNotEmpty ? availableSlaveIds.first : null;
  List<SensorZone> zones =
      selectedSlaveId != null ? availableZonesForSlave(selectedSlaveId) : [];
  SensorZone? selectedZone = zones.isNotEmpty ? zones.first : null;

  String defaultName() {
    if (selectedSlaveId == null || selectedZone == null) return '';
    final model = ModbusRtu.slaveModelMap[selectedSlaveId] ?? 'Slave $selectedSlaveId';
    return '$model - ${selectedZone!.label}';
  }

  final nameController = TextEditingController(text: defaultName());
  final locationController = TextEditingController();
  final notesController = TextEditingController();

  return showDialog<PlacedSensor>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Icon(type.icon, color: type.color),
                const SizedBox(width: 8),
                Text('Place ${type.label} Sensor'),
              ],
            ),
            content: availableSlaveIds.isEmpty
                ? const Text(
                    'Every scanned device already has all its zones pinned.',
                    style: TextStyle(color: Colors.grey),
                  )
                : SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _TvSelectField<int>(
                          label: 'Device',
                          autofocus: true,
                          options: availableSlaveIds,
                          value: selectedSlaveId,
                          labelBuilder: (id) =>
                              'Slave $id - ${ModbusRtu.slaveModelMap[id] ?? ""}',
                          onChanged: (value) {
                            setDialogState(() {
                              selectedSlaveId = value;
                              zones = value != null
                                  ? availableZonesForSlave(value)
                                  : [];
                              selectedZone =
                                  zones.isNotEmpty ? zones.first : null;
                              nameController.text = defaultName();
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        _TvSelectField<int>(
                          label: 'Zone',
                          options: [for (final z in zones) z.address],
                          value: selectedZone?.address,
                          labelBuilder: (address) => zones
                              .firstWhere((z) => z.address == address)
                              .label,
                          onChanged: (value) {
                            setDialogState(() {
                              selectedZone = zones
                                  .firstWhere((z) => z.address == value);
                              nameController.text = defaultName();
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: nameController,
                          decoration: const InputDecoration(labelText: 'Name'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: locationController,
                          decoration:
                              const InputDecoration(labelText: 'Location'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: notesController,
                          maxLines: 3,
                          decoration: const InputDecoration(labelText: 'Notes'),
                        ),
                      ],
                    ),
                  ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              if (availableSlaveIds.isNotEmpty)
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: (selectedSlaveId == null || selectedZone == null)
                      ? null
                      : () {
                          Navigator.pop(
                            context,
                            PlacedSensor(
                              slaveId: selectedSlaveId!,
                              zoneAddress: selectedZone!.address,
                              zoneLabel: selectedZone!.label,
                              type: type,
                              name: nameController.text.trim().isEmpty
                                  ? defaultName()
                                  : nameController.text.trim(),
                              location: locationController.text.trim(),
                              notes: notesController.text.trim(),
                              xFraction: xFraction,
                              yFraction: yFraction,
                            ),
                          );
                        },
                  child: const Text('Place'),
                ),
            ],
          );
        },
      );
    },
  );
}

////////////////////////////////////////////////////////////
/// EDIT EXISTING PIN
////////////////////////////////////////////////////////////

Future<PlacedSensor?> showEditSensorDialog(
  BuildContext context, {
  required PlacedSensor sensor,
  required VoidCallback onRemove,
}) {
  final nameController = TextEditingController(text: sensor.name);
  final locationController = TextEditingController(text: sensor.location);
  final notesController = TextEditingController(text: sensor.notes);

  return showDialog<PlacedSensor>(
    context: context,
    builder: (context) {
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(sensor.type.icon, color: sensor.type.color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Slave ${sensor.slaveId} - ${sensor.zoneLabel}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: locationController,
                decoration: const InputDecoration(labelText: 'Location'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesController,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            onPressed: () {
              onRemove();
              Navigator.pop(context);
            },
            child: const Text('Remove'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              final updated = sensor.copyWith(
                name: nameController.text.trim().isEmpty
                    ? sensor.name
                    : nameController.text.trim(),
                location: locationController.text.trim(),
                notes: notesController.text.trim(),
              );
              Navigator.pop(context, updated);
            },
            child: const Text('Save'),
          ),
        ],
      );
    },
  );
}

////////////////////////////////////////////////////////////
/// TV-REMOTE-FRIENDLY SELECT FIELD
///
/// DropdownButtonFormField opens its options in a separate popup route,
/// which is unreliable to reach with a D-pad on many Android TV boxes —
/// and once that popup is dismissed, focus can fail to return cleanly to
/// the dialog, which also breaks navigating on to fields below it (e.g.
/// Location). This avoids the popup entirely: the current value is shown
/// in place, and Left/Right (D-pad, keyboard, or the on-screen chevrons
/// for mouse/touch) steps through [options] without ever leaving the
/// dialog's focus scope.
////////////////////////////////////////////////////////////

class _TvSelectField<T> extends StatefulWidget {
  final String label;
  final List<T> options;
  final T? value;
  final String Function(T) labelBuilder;
  final ValueChanged<T?> onChanged;
  final bool autofocus;

  const _TvSelectField({
    super.key,
    required this.label,
    required this.options,
    required this.value,
    required this.labelBuilder,
    required this.onChanged,
    this.autofocus = false,
  });

  @override
  State<_TvSelectField<T>> createState() => _TvSelectFieldState<T>();
}

class _TvSelectFieldState<T> extends State<_TvSelectField<T>> {
  final FocusNode _focusNode = FocusNode();
  bool _focused = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  int get _currentIndex {
    final value = widget.value;
    if (value == null) return -1;
    return widget.options.indexOf(value);
  }

  void _step(int delta) {
    if (widget.options.isEmpty) return;
    final current = _currentIndex;
    final nextIndex = current < 0
        ? 0
        : (current + delta).clamp(0, widget.options.length - 1);
    if (nextIndex == current) return;
    widget.onChanged(widget.options[nextIndex]);
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      _step(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _step(1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // Bare GestureDetector (not IconButton) on purpose — it lets mouse/touch
  // still nudge the value without adding an extra focus stop that would
  // otherwise sit between this field and its neighbours during D-pad
  // navigation.
  Widget _chevron(IconData icon, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor:
            onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Icon(
            icon,
            size: 20,
            color: onTap == null ? Colors.grey.shade300 : Colors.black54,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final disabled = widget.options.isEmpty;
    final index = _currentIndex;
    final currentLabel = (widget.value != null)
        ? widget.labelBuilder(widget.value as T)
        : (disabled ? 'None available' : '');

    return Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      onFocusChange: (focused) {
        if (!mounted) return;
        setState(() => _focused = focused);
      },
      onKeyEvent: disabled ? null : _onKeyEvent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          border: Border.all(
            color: _focused ? Colors.teal : Colors.grey.shade400,
            width: _focused ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            _chevron(
              Icons.chevron_left,
              (disabled || index <= 0) ? null : () => _step(-1),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.label,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                  Text(
                    currentLabel,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      color: disabled ? Colors.grey : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            _chevron(
              Icons.chevron_right,
              (disabled || index >= widget.options.length - 1)
                  ? null
                  : () => _step(1),
            ),
          ],
        ),
      ),
    );
  }
}
