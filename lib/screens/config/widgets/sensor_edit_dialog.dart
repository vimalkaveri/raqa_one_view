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
                        DropdownButtonFormField<int>(
                          value: selectedSlaveId,
                          decoration:
                              const InputDecoration(labelText: 'Device'),
                          items: [
                            for (final id in availableSlaveIds)
                              DropdownMenuItem(
                                value: id,
                                child: Text(
                                  'Slave $id - ${ModbusRtu.slaveModelMap[id] ?? ""}',
                                ),
                              ),
                          ],
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
                        DropdownButtonFormField<int>(
                          value: selectedZone?.address,
                          decoration: const InputDecoration(labelText: 'Zone'),
                          items: [
                            for (final zone in zones)
                              DropdownMenuItem(
                                value: zone.address,
                                child: Text(zone.label),
                              ),
                          ],
                          onChanged: zones.isEmpty
                              ? null
                              : (value) {
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
