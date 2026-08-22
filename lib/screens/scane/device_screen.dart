import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../devices/router/scan_device_signature.dart';

import '../../services/rs485/modbus_rtu.dart';
import '../../services/rs485/rs485_service.dart';
import '../../services/scanning/device_scanning.dart';
import '../../services/scanning/mini_register_preview.dart';
import '../../services/settings/app_settings.dart';
class DeviceScreen extends StatefulWidget {
  final Rs485Service manager;

  const DeviceScreen({super.key, required this.manager});

  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen> {
  Set<int> enabledSlaves = {};
  Map<int, String> slaveModels = {};

  late DeviceScanning scanner;

  bool isScanning = false;

  int selectedIndex = 0;

  static const int columns = 7;
  static const int totalSlaves = 31;

  // One key per grid tile, used to auto-scroll the selected tile into view
  // during keyboard/remote D-pad navigation — GridView is already
  // touch-scrollable, but nothing previously kept the focused tile visible
  // when navigating past the bottom of the viewport with arrow keys.
  final List<GlobalKey> _tileKeys =
  List.generate(totalSlaves, (_) => GlobalKey());

  int get maxIndex => totalSlaves + 2;

  ////////////////////////////////////////////////////////////
  /// INIT
  ////////////////////////////////////////////////////////////

  @override
  void initState() {
    super.initState();
    scanner = DeviceScanning(manager: widget.manager);
    loadSavedSettings();
  }

  ////////////////////////////////////////////////////////////
  /// LOAD SETTINGS
  ////////////////////////////////////////////////////////////

  Future<void> loadSavedSettings() async {
    await ModbusRtu.loadSettings();

    if (!mounted) return;

    setState(() {
      enabledSlaves = ModbusRtu.slaveIds.toSet();
      slaveModels = Map<int, String>.from(ModbusRtu.slaveModelMap);
    });

    if (enabledSlaves.isNotEmpty) {
      await widget.manager.applyNewSlaveConfiguration();
    }
  }

  ////////////////////////////////////////////////////////////
  /// SCAN DEVICES
  ////////////////////////////////////////////////////////////

  Future<void> startScan() async {
    if (isScanning) return;

    setState(() {
      isScanning = true;
      enabledSlaves.clear();
      slaveModels.clear();
    });

    try {
      final detected = await scanner.scanSlaves();

      enabledSlaves = detected.keys.toSet();

      for (final e in detected.entries) {
        slaveModels[e.key] = e.value.modelName;
      }

      ModbusRtu.slaveIds = enabledSlaves.toList()..sort();
      ModbusRtu.slaveModelMap = Map<int, String>.from(slaveModels);

      if (enabledSlaves.isNotEmpty) {
        await widget.manager.applyNewSlaveConfiguration();
      }
    } catch (e) {
      debugPrint("Scan error: $e");
    }

    if (!mounted) return;

    setState(() {
      isScanning = false;
    });
  }

  ////////////////////////////////////////////////////////////
  /// SAVE SETTINGS
  ////////////////////////////////////////////////////////////

  Future<void> saveSettings() async {
    ModbusRtu.slaveIds = enabledSlaves.toList()..sort();
    ModbusRtu.slaveModelMap = Map<int, String>.from(slaveModels);

    await ModbusRtu.saveSettings();

    if (enabledSlaves.isNotEmpty) {
      await widget.manager.applyNewSlaveConfiguration();
    }

    if (!mounted) return;

    Navigator.pop(context, enabledSlaves);
  }

  ////////////////////////////////////////////////////////////
  /// INDEX CONTROL
  ////////////////////////////////////////////////////////////

  void _updateIndex(int newIndex) {
    if (newIndex < 0) newIndex = 0;
    if (newIndex > maxIndex) newIndex = maxIndex;

    setState(() => selectedIndex = newIndex);

    final tileIndex = newIndex - 3; // 0..2 are the top-bar buttons
    if (tileIndex >= 0 && tileIndex < totalSlaves) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _tileKeys[tileIndex].currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            alignment: 0.5,
          );
        }
      });
    }
  }

  ////////////////////////////////////////////////////////////
  /// KEYBOARD NAVIGATION
  ////////////////////////////////////////////////////////////

  void handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _updateIndex(selectedIndex + 1);
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _updateIndex(selectedIndex - 1);
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (selectedIndex < 3) {
        _updateIndex(3);
      } else {
        _updateIndex(selectedIndex + columns);
      }
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (selectedIndex >= 3 && selectedIndex < 3 + columns) {
        _updateIndex(1);
      } else {
        _updateIndex(selectedIndex - columns);
      }
    }

    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.select) {
      if (selectedIndex == 0) {
        Navigator.pop(context);
      } else if (selectedIndex == 1 && !isScanning) {
        startScan();
      } else if (selectedIndex == 2 && enabledSlaves.isNotEmpty) {
        saveSettings();
      } else if (selectedIndex >= 3) {
        final slaveId = selectedIndex - 3 + 1;
        if (enabledSlaves.contains(slaveId) &&
            slaveModels.containsKey(slaveId)) {
          _showEditSlaveDialog(
            context,
            slaveId,
            slaveModels[slaveId]!,
          );
        }
      }
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.pop(context);
    }
  }

  ////////////////////////////////////////////////////////////
  /// EDIT SLAVE — display name, plus an optional user-assigned priority
  /// order.
  ///
  /// Name is purely cosmetic — this only touches `slaveModels` (display
  /// name), never `ModbusRtu.slaveTypeMap`. Device routing is keyed off
  /// the type recorded by the scanner, so renaming a slave here can
  /// never accidentally change which dashboard/register set it uses.
  ///
  /// Priority is only editable when Settings > Priority is enabled. It's
  /// entirely optional — leave the field blank and the slave simply has
  /// no priority (no badge, sits behind every prioritized device). When
  /// several floor-plan images are in play and more than one device
  /// alarms at once, this priority order is what the Dashboard uses to
  /// decide which device's alert takes precedence.
  ////////////////////////////////////////////////////////////

  void _showEditSlaveDialog(
      BuildContext context,
      int slaveId,
      String currentName,
      ) {
    final nameController = TextEditingController(text: currentName)
      ..selection = TextSelection(
        baseOffset: 0,
        extentOffset: currentName.length,
      );

    final priorityEnabled = AppSettings.priorityEnabled;
    final currentPriority = ModbusRtu.priorityForSlave(slaveId);
    final priorityController = TextEditingController(
      text: currentPriority?.toString() ?? '',
    );

    Future<void> save(BuildContext dialogContext) async {
      final newName = nameController.text.trim();
      if (newName.isNotEmpty) {
        setState(() => slaveModels[slaveId] = newName);
      }

      if (priorityEnabled) {
        final priorityText = priorityController.text.trim();
        if (priorityText.isEmpty) {
          await ModbusRtu.clearPriorityForSlave(slaveId);
        } else {
          final parsed = int.tryParse(priorityText);
          if (parsed != null && parsed > 0) {
            await ModbusRtu.setPriorityForSlave(slaveId, parsed);
          }
        }
        if (mounted) setState(() {});
      }

      if (dialogContext.mounted) Navigator.pop(dialogContext);
    }

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              const Icon(Icons.edit_note, color: Colors.orange),
              const SizedBox(width: 8),
              Text('Slave $slaveId'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Model name',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () => nameController.clear(),
                  ),
                ),
                onSubmitted: priorityEnabled ? null : (_) => save(context),
              ),
              if (priorityEnabled) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: priorityController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: 'Priority order (optional)',
                    helperText:
                        'Lower number = higher priority. Leave blank for none.',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () => priorityController.clear(),
                    ),
                  ),
                  onSubmitted: (_) => save(context),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () => save(context),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  ////////////////////////////////////////////////////////////
  /// UI
  ////////////////////////////////////////////////////////////

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        handleKey(event);
        return KeyEventResult.handled;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              //////////////////////////////////////////////////////////
              /// TOP BAR
              //////////////////////////////////////////////////////////

              Container(
                height: 65,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    _topButton(
                      index: 0,
                      child: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Spacer(),
                    const Text(
                      "Configuration",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        _topButton(
                          index: 1,
                          child: Text(
                            isScanning ? "SCANNING..." : "SCAN",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          onPressed: isScanning ? null : startScan,
                        ),
                        const SizedBox(width: 10),
                        _topButton(
                          index: 2,
                          child: const Text(
                            "OK",
                            style: TextStyle(
                              color: Colors.green,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          onPressed: enabledSlaves.isEmpty ? null : saveSettings,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              //////////////////////////////////////////////////////////
              /// GRID
              //////////////////////////////////////////////////////////

              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: GridView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: totalSlaves,
                    gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 1.2,
                    ),
                    itemBuilder: (context, index) {
                      final slaveId = index + 1;
                      final isEnabled = enabledSlaves.contains(slaveId);
                      final isSelected = selectedIndex == index + 3;
                      final canEdit =
                          isEnabled && slaveModels.containsKey(slaveId);
                      final priority = ModbusRtu.priorityForSlave(slaveId);

                      final tile = ClipRRect(
                        key: _tileKeys[index],
                        borderRadius: BorderRadius.circular(12),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: canEdit
                                  ? () {
                                _updateIndex(index + 3);
                                _showEditSlaveDialog(
                                  context,
                                  slaveId,
                                  slaveModels[slaveId]!,
                                );
                              }
                                  : null,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 120),
                                decoration: BoxDecoration(
                                  color: isEnabled
                                      ? Colors.green.withOpacity(0.15)
                                      : Colors.white.withOpacity(0.04),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isSelected
                                        ? Colors.orange
                                        : Colors.white.withOpacity(0.15),
                                    width: isSelected ? 3 : 1,
                                  ),
                                ),
                                padding: const EdgeInsets.all(6),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      "Slave $slaveId",
                                      style: TextStyle(
                                        color: isEnabled
                                            ? Colors.white
                                            : Colors.grey,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 8,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    if (isScanning && !isEnabled)
                                      const SizedBox(
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    else if (canEdit)
                                      SizedBox(
                                        height: 32,
                                        child: DeviceRegisterPreview(
                                          manager: widget.manager,
                                          slaveIndex: slaveId - 1,
                                          type: ModbusRtu
                                              .slaveTypeMap[slaveId] ??
                                              DeviceType.fsa,
                                        ),
                                      ),
                                    if (canEdit)
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Flexible(
                                            child: Text(
                                              slaveModels[slaveId]!,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: Colors.white70,
                                              ),
                                            ),
                                          ),
                                          /*const SizedBox(width: 4),
                                          const Icon(
                                            Icons.edit,
                                            size: 12,
                                            color: Colors.white38,
                                          ),*/
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );

                      // Priority badge (top-right corner) — only shown for
                      // enabled/scanned slaves, and only when priority
                      // display is turned on in Settings.
                      if (!canEdit ||
                          priority == null ||
                          !AppSettings.priorityEnabled) {
                        return tile;
                      }

                      return Stack(
                        children: [
                          tile,
                          Positioned(
                            top: 4,
                            right: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black87,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.orange),
                              ),
                              child: Text(
                                'P$priority',
                                style: const TextStyle(
                                  color: Colors.orange,
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  ////////////////////////////////////////////////////////////
  /// TOP BUTTON
  ////////////////////////////////////////////////////////////

  Widget _topButton({
    required int index,
    required Widget child,
    required VoidCallback? onPressed,
  }) {
    final selected = selectedIndex == index;

    return GestureDetector(
      onTap: onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.orange : Colors.grey[900],
          borderRadius: BorderRadius.circular(8),
        ),
        child: child,
      ),
    );
  }
}