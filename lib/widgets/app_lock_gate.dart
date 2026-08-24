// ==========================
// File: widgets/app_lock_gate.dart
//
// Password gate for individual screens. Wrap a screen's widget with
// AppLockGate(child: ...) at the point it's navigated to (see
// HomeScreen's menu item screenBuilders) and it will show a PIN entry
// screen first, only revealing the wrapped screen once the correct
// AppSettings.password has been entered.
//
// The lock state lives in this widget's own State, so it's re-armed
// every time the wrapped screen is (re)navigated to — there's no way
// to stay "already unlocked" across visits, by design.
//
// If AppSettings.password is empty, the gate is skipped entirely (no
// password set = no lock). The app ships with a default password of
// '0000' (see AppSettings), so out of the box this gate is active.
// ==========================

import 'package:flutter/material.dart';

import '../services/settings/app_settings.dart';
import '../utils/app_theme.dart';

class AppLockGate extends StatefulWidget {
  final Widget child;

  const AppLockGate({super.key, required this.child});

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> {
  late bool _locked = AppSettings.password.isNotEmpty;
  final TextEditingController _pinController = TextEditingController();
  String? _pinError;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

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

  @override
  Widget build(BuildContext context) {
    if (!_locked) return widget.child;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock, size: 56, color: Colors.tealAccent),
                const SizedBox(height: 16),
                Text(
                  'Locked',
                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 20),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _pinController,
                  obscureText: true,
                  autofocus: true,
                  style: TextStyle(color: AppTheme.textPrimary),
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
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => Navigator.maybePop(context),
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
