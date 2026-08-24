// ==========================
// File: screens/setting/setting_page.dart
//
// Settings screen:
//   - Siren on/off        : persisted intent (AppSettings.sirenEnabled).
//                            NOTE: this currently only stores the desired
//                            state — Rs485Service does not yet implement
//                            a Modbus "write register" frame (it only
//                            reads), so no command is sent to the bus
//                            yet. Wiring that up is a follow-up once a
//                            write-capable frame parser is added.
//   - Backup               : dumps the current slave/priority
//                            configuration as JSON so it can be copied
//                            out and restored later.
//   - Reset password       : sets the local app-lock password
//                            (AppSettings.password).
//   - Priority enable/disable : toggles whether the "P<n>" priority
//                            badge shows on the Devices screen.
// ==========================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/rs485/modbus_rtu.dart';
import '../../services/settings/app_settings.dart';
import '../../utils/app_theme.dart';

class SettingScreen extends StatefulWidget {
  const SettingScreen({super.key});

  @override
  State<SettingScreen> createState() => _SettingScreenState();
}

class _SettingScreenState extends State<SettingScreen> {
  static const double _pinSizeStep = 2.0;

  final FocusNode _pinSizeFocusNode =
      FocusNode(debugLabel: 'pinSizeControl');
  bool _pinSizeFocused = false;

  @override
  void dispose() {
    _pinSizeFocusNode.dispose();
    super.dispose();
  }

  void _adjustPinSize(double delta) {
    final next = (AppSettings.pinSize + delta)
        .clamp(AppSettings.minPinSize, AppSettings.maxPinSize);
    setState(() => AppSettings.pinSize = next);
    AppSettings.setPinSize(next);
  }

  /// Only handles Left/Right (decrease/increase). Up/Down are deliberately
  /// left as `ignored` — Flutter's built-in Slider treats all four arrow
  /// keys as +/- once it has D-pad focus, which traps a remote/D-pad user
  /// on this one control with no way to reach Priority, Backup, etc. above
  /// or below it. Returning `ignored` here lets Up/Down fall through to
  /// normal directional focus traversal instead, same as every other
  /// focusable control on this screen.
  KeyEventResult _handlePinSizeKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _adjustPinSize(_pinSizeStep);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _adjustPinSize(-_pinSizeStep);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const _SectionHeader('Appearance'),
          SwitchListTile(
            secondary: Icon(Icons.dark_mode, color: Colors.tealAccent),
            title: Text('Dark Mode', style: TextStyle(color: AppTheme.textPrimary)),
            subtitle: Text(
              'Use a dark color scheme across the whole app',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
            value: AppSettings.darkModeEnabled,
            onChanged: (value) async {
              await AppSettings.setDarkModeEnabled(value);
              if (mounted) setState(() {});
            },
          ),
          Divider(color: AppTheme.divider, height: 1),

          const _SectionHeader('Alarm'),
          SwitchListTile(
            secondary: const Icon(Icons.campaign, color: Colors.orange),
            title: Text('Siren', style: TextStyle(color: AppTheme.textPrimary)),
            subtitle: Text(
              'Turn the siren output on or off',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
            value: AppSettings.sirenEnabled,
            onChanged: (value) async {
              await AppSettings.setSirenEnabled(value);
              if (mounted) setState(() {});
            },
          ),
          Divider(color: AppTheme.divider, height: 1),

          const _SectionHeader('Devices'),
          SwitchListTile(
            secondary: const Icon(Icons.low_priority, color: Colors.tealAccent),
            title: Text('Priority', style: TextStyle(color: AppTheme.textPrimary)),
            subtitle: Text(
              'Show the priority badge on the Devices screen',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
            value: AppSettings.priorityEnabled,
            onChanged: (value) async {
              await AppSettings.setPriorityEnabled(value);
              if (mounted) setState(() {});
            },
          ),
          Divider(color: AppTheme.divider, height: 1),

          const _SectionHeader('Dashboard'),
          Focus(
            focusNode: _pinSizeFocusNode,
            onKeyEvent: _handlePinSizeKey,
            onFocusChange: (focused) =>
                setState(() => _pinSizeFocused = focused),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color:
                      _pinSizeFocused ? Colors.tealAccent : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.control_camera, color: Colors.tealAccent),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Sensor pin size',
                            style: TextStyle(color: AppTheme.textPrimary)),
                        const SizedBox(height: 2),
                        Text(
                          'Use Left / Right to adjust',
                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon:
                        Icon(Icons.chevron_left, color: AppTheme.textPrimary),
                    onPressed: () => _adjustPinSize(-_pinSizeStep),
                  ),
                  SizedBox(
                    width: 44,
                    child: Text(
                      '${AppSettings.pinSize.round()}px',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.tealAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon:
                        Icon(Icons.chevron_right, color: AppTheme.textPrimary),
                    onPressed: () => _adjustPinSize(_pinSizeStep),
                  ),
                ],
              ),
            ),
          ),
          Divider(color: AppTheme.divider, height: 1),

          const _SectionHeader('System'),
          ListTile(
            leading: const Icon(Icons.backup, color: Colors.tealAccent),
            title: Text('Backup', style: TextStyle(color: AppTheme.textPrimary)),
            subtitle: Text(
              'Export the current device configuration',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
            onTap: _showBackupDialog,
          ),
          ListTile(
            leading: const Icon(Icons.lock_reset, color: Colors.orange),
            title: Text('Reset Password',
                style: TextStyle(color: AppTheme.textPrimary)),
            subtitle: Text(
              'Change the app-lock password',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
            onTap: _showPasswordDialog,
          ),
        ],
      ),
    );
  }

  ////////////////////////////////////////////////////////////
  /// BACKUP
  ////////////////////////////////////////////////////////////

  void _showBackupDialog() {
    final data = {
      'slaveIds': ModbusRtu.slaveIds,
      'slaveNames': ModbusRtu.slaveNames.map((k, v) => MapEntry('$k', v)),
      'slaveModels': ModbusRtu.slaveModelMap.map((k, v) => MapEntry('$k', v)),
      'slaveTypes':
          ModbusRtu.slaveTypeMap.map((k, v) => MapEntry('$k', v.name)),
      'slavePriorities':
          ModbusRtu.slavePriorityMap.map((k, v) => MapEntry('$k', v)),
      'baudRate': ModbusRtu.baudRate,
      'pollIntervalMs': ModbusRtu.pollIntervalMs,
    };

    final json = const JsonEncoder.withIndent('  ').convert(data);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Backup'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: SelectableText(
                json,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copy'),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: json));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied to clipboard')),
                );
              },
            ),
          ],
        );
      },
    );
  }

  ////////////////////////////////////////////////////////////
  /// RESET PASSWORD
  ////////////////////////////////////////////////////////////

  void _showPasswordDialog() {
    final currentController = TextEditingController();
    final newController = TextEditingController();
    final confirmController = TextEditingController();
    String? error;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: const Text('Reset Password'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (AppSettings.password.isNotEmpty)
                    TextField(
                      controller: currentController,
                      obscureText: true,
                      decoration:
                          const InputDecoration(labelText: 'Current password'),
                    ),
                  TextField(
                    controller: newController,
                    obscureText: true,
                    decoration:
                        const InputDecoration(labelText: 'New password'),
                  ),
                  TextField(
                    controller: confirmController,
                    obscureText: true,
                    decoration: const InputDecoration(
                        labelText: 'Confirm new password'),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(error!,
                        style: const TextStyle(color: Colors.redAccent)),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    FocusScope.of(context).unfocus();
                    Navigator.pop(context);
                  },
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                  onPressed: () async {
                    if (AppSettings.password.isNotEmpty &&
                        currentController.text != AppSettings.password) {
                      setDialogState(() => error = 'Current password is incorrect');
                      return;
                    }
                    if (newController.text.isEmpty) {
                      setDialogState(() => error = 'New password cannot be empty');
                      return;
                    }
                    if (newController.text != confirmController.text) {
                      setDialogState(() => error = 'Passwords do not match');
                      return;
                    }

                    await AppSettings.setPassword(newController.text);
                    if (context.mounted) {
                      FocusScope.of(context).unfocus();
                      Navigator.pop(context);
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: Colors.tealAccent,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}
