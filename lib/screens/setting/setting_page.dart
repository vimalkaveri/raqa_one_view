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

class SettingScreen extends StatefulWidget {
  const SettingScreen({super.key});

  @override
  State<SettingScreen> createState() => _SettingScreenState();
}

class _SettingScreenState extends State<SettingScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const _SectionHeader('Alarm'),
          SwitchListTile(
            secondary: const Icon(Icons.campaign, color: Colors.orange),
            title: const Text('Siren', style: TextStyle(color: Colors.white)),
            subtitle: const Text(
              'Turn the siren output on or off',
              style: TextStyle(color: Colors.grey),
            ),
            value: AppSettings.sirenEnabled,
            onChanged: (value) async {
              await AppSettings.setSirenEnabled(value);
              if (mounted) setState(() {});
            },
          ),
          const Divider(color: Colors.white24, height: 1),

          const _SectionHeader('Devices'),
          SwitchListTile(
            secondary: const Icon(Icons.low_priority, color: Colors.tealAccent),
            title: const Text('Priority', style: TextStyle(color: Colors.white)),
            subtitle: const Text(
              'Show the priority badge on the Devices screen',
              style: TextStyle(color: Colors.grey),
            ),
            value: AppSettings.priorityEnabled,
            onChanged: (value) async {
              await AppSettings.setPriorityEnabled(value);
              if (mounted) setState(() {});
            },
          ),
          const Divider(color: Colors.white24, height: 1),

          const _SectionHeader('System'),
          ListTile(
            leading: const Icon(Icons.backup, color: Colors.tealAccent),
            title: const Text('Backup', style: TextStyle(color: Colors.white)),
            subtitle: const Text(
              'Export the current device configuration',
              style: TextStyle(color: Colors.grey),
            ),
            onTap: _showBackupDialog,
          ),
          ListTile(
            leading: const Icon(Icons.lock_reset, color: Colors.orange),
            title: const Text('Reset Password',
                style: TextStyle(color: Colors.white)),
            subtitle: const Text(
              'Change the app-lock password',
              style: TextStyle(color: Colors.grey),
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
                  onPressed: () => Navigator.pop(context),
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
                    if (context.mounted) Navigator.pop(context);
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
