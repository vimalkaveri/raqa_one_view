// ==========================
// File: screens/config/widgets/sensor_edit_dialog.dart
//
// Two entry points:
//   - showAssignSensorDialog: used right after a sensor-type icon is
//     dropped onto the image. The user picks which scanned slave AND
//     which zone on that slave (a slave can have more than one physical
//     sensor zone — see sensor_zones.dart) this pin represents, then can
//     set name/location.
//   - showEditSensorDialog: used when tapping an already-placed pin.
//     The slave/zone/type are fixed; name/location stay editable,
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
  final locationFocusNode = FocusNode(debugLabel: 'sensor_location_field');

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
                        _TvTextField(
                          label: 'Name',
                          controller: nameController,
                          textInputAction: TextInputAction.next,
                          nextFocusNode: locationFocusNode,
                        ),
                        const SizedBox(height: 12),
                        _TvTextField(
                          label: 'Location',
                          controller: locationController,
                          focusNode: locationFocusNode,
                          textInputAction: TextInputAction.done,
                        ),
                      ],
                    ),
                  ),
            actions: [
              TextButton(
                onPressed: () {
                  // Unfocus before popping — closing a dialog while one of
                  // its TextFields still holds focus (Name is autofocused)
                  // can crash with a BuildScope assertion mid-frame.
                  FocusScope.of(context).unfocus();
                  Navigator.pop(context);
                },
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
                          FocusScope.of(context).unfocus();
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
  ).whenComplete(() {
    // Deferred a frame — disposing a FocusNode still tangled up in the
    // dialog's own closing/pop transition can trigger the same
    // mid-frame BuildScope crash the unfocus() calls above guard
    // against elsewhere in this dialog.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      locationFocusNode.dispose();
    });
  });
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
  final locationFocusNode = FocusNode(debugLabel: 'sensor_location_field');

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
              _TvTextField(
                label: 'Name',
                controller: nameController,
                autofocus: true,
                textInputAction: TextInputAction.next,
                nextFocusNode: locationFocusNode,
              ),
              const SizedBox(height: 12),
              _TvTextField(
                label: 'Location',
                controller: locationController,
                focusNode: locationFocusNode,
                textInputAction: TextInputAction.done,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            onPressed: () {
              FocusScope.of(context).unfocus();
              onRemove();
              Navigator.pop(context);
            },
            child: const Text('Remove'),
          ),
          TextButton(
            onPressed: () {
              FocusScope.of(context).unfocus();
              Navigator.pop(context);
            },
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
              );
              FocusScope.of(context).unfocus();
              Navigator.pop(context, updated);
            },
            child: const Text('Save'),
          ),
        ],
      );
    },
  ).whenComplete(() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      locationFocusNode.dispose();
    });
  });
}

////////////////////////////////////////////////////////////
/// TV-REMOTE-FRIENDLY TEXT FIELD
///
/// A plain TextField opens the on-screen keyboard the instant it gains
/// focus — including just from D-pad navigation landing on it, which
/// is unwanted here: the field should only start with a real keyboard
/// once the user explicitly selects it (Select/Enter on a remote, or a
/// tap/click). Until then it's just a highlighted, non-editing display
/// box.
///
/// This decouples the two: an outer Focus node is what D-pad navigation
/// actually lands on (shows the teal highlight, nothing else); Select
/// or a tap swaps in a real TextField and focuses *that*, which is what
/// triggers the keyboard. Finishing (Done/Next on the keyboard, tapping
/// elsewhere, or Back/Escape) swaps back to the display box.
////////////////////////////////////////////////////////////

class _TvTextField extends StatefulWidget {
  final String label;
  final TextEditingController controller;
  final TextInputAction textInputAction;
  final FocusNode? focusNode;
  final FocusNode? nextFocusNode;
  final bool autofocus;

  const _TvTextField({
    required this.label,
    required this.controller,
    this.textInputAction = TextInputAction.done,
    this.focusNode,
    this.nextFocusNode,
    this.autofocus = false,
  });

  @override
  State<_TvTextField> createState() => _TvTextFieldState();
}

class _TvTextFieldState extends State<_TvTextField> {
  late final FocusNode _outerFocusNode = widget.focusNode ?? FocusNode();
  final FocusNode _innerFocusNode = FocusNode();
  bool _editing = false;
  bool _focused = false;

  @override
  void dispose() {
    // Only dispose the outer node if we created it ourselves — when the
    // caller supplies one (for cross-field D-pad chaining), it owns it.
    if (widget.focusNode == null) _outerFocusNode.dispose();
    _innerFocusNode.dispose();
    super.dispose();
  }

  void _startEditing() {
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _innerFocusNode.requestFocus();
    });
  }

  void _stopEditing({bool advanceToNext = false}) {
    if (!_editing) return;
    setState(() => _editing = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Advancing (Done/Next pressed on the keyboard) only moves the
      // D-pad highlight to the next field — it deliberately does NOT
      // open that field's keyboard too; that still needs its own
      // explicit Select/tap.
      if (advanceToNext && widget.nextFocusNode != null) {
        widget.nextFocusNode!.requestFocus();
      } else {
        _outerFocusNode.requestFocus();
      }
    });
  }

  KeyEventResult _onOuterKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.numpadEnter) {
      _startEditing();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final isEmpty = widget.controller.text.trim().isEmpty;

    return Focus(
      focusNode: _outerFocusNode,
      autofocus: widget.autofocus,
      onFocusChange: (focused) {
        if (!mounted) return;
        setState(() => _focused = focused);
      },
      // While editing, the real TextField below owns keyboard focus and
      // handles its own keys — this outer handler steps aside so it
      // doesn't compete for Enter/Select.
      onKeyEvent: _editing ? null : _onOuterKeyEvent,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _editing ? null : _startEditing,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity((_focused || _editing) ? 0.08 : 0.04),
            border: Border.all(
              color: (_focused || _editing) ? Colors.teal : Colors.white24,
              width: (_focused || _editing) ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Expanded(
                child: _editing
                    ? Focus(
                        // Not a separate focus stop — just intercepts
                        // Back/Escape bubbling up from the real TextField
                        // so a remote's Back button can bail out of
                        // editing without submitting.
                        canRequestFocus: false,
                        onKeyEvent: (node, event) {
                          if (event is KeyDownEvent &&
                              (event.logicalKey == LogicalKeyboardKey.escape ||
                                  event.logicalKey ==
                                      LogicalKeyboardKey.goBack)) {
                            _stopEditing();
                            return KeyEventResult.handled;
                          }
                          return KeyEventResult.ignored;
                        },
                        child: TextField(
                          controller: widget.controller,
                          focusNode: _innerFocusNode,
                          autofocus: true,
                          textInputAction: widget.textInputAction,
                          cursorColor: Colors.tealAccent,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                          decoration: InputDecoration(
                            labelText: widget.label,
                            labelStyle: const TextStyle(
                              color: Colors.tealAccent,
                              fontSize: 11,
                            ),
                            isDense: true,
                            isCollapsed: false,
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onSubmitted: (_) =>
                              _stopEditing(advanceToNext: true),
                          onTapOutside: (_) => _stopEditing(),
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.label,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isEmpty ? 'Tap to enter' : widget.controller.text,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontStyle:
                                  isEmpty ? FontStyle.italic : FontStyle.normal,
                              color: isEmpty ? Colors.grey : Colors.white,
                            ),
                          ),
                        ],
                      ),
              ),
              const SizedBox(width: 8),
              Icon(
                _editing ? Icons.check_circle_outline : Icons.edit_outlined,
                size: 18,
                color: (_focused || _editing) ? Colors.tealAccent : Colors.white38,
              ),
            ],
          ),
        ),
      ),
    );
  }
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
            color: onTap == null ? Colors.grey.shade700 : Colors.white70,
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
            color: _focused ? Colors.teal : Colors.white24,
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
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  Text(
                    currentLabel,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      color: disabled ? Colors.grey : Colors.white,
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
