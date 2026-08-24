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
//
// INPUT SUPPORT — this screen is reachable via all four input methods:
//   - Touchscreen/mouse: tap the on-screen keypad tiles, or Unlock/Cancel.
//   - Remote (D-pad, no keyboard): arrow keys move a single highlighted
//     selection across the keypad grid then down into Unlock/Cancel;
//     Select/Enter activates whatever's highlighted; Back/Escape cancels.
//   - Physical/Bluetooth keyboard: digit keys and Backspace are handled
//     directly, without needing to move the highlight at all.
// The PIN field itself is read-only — it's a *display* of what's been
// entered so far, not a text-input target. That sidesteps Android TV's
// on-screen-keyboard/IME popping up over a remote-first screen; every
// input method writes into the same controller through the same path.
// ==========================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/settings/app_settings.dart';
import '../utils/app_theme.dart';

class AppLockGate extends StatefulWidget {
  final Widget child;

  const AppLockGate({super.key, required this.child});

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

// Flat selection index across the whole locked screen:
//   0-8   -> digits 1-9 (3x3 grid)
//   9     -> Clear
//   10    -> digit 0
//   11    -> Backspace
//   12    -> Unlock
//   13    -> Cancel
// Same "single flat index + row/col math" convention used by the grids
// in device_screen.dart and home_screen.dart.
const int _kClearIndex = 9;
const int _kZeroIndex = 10;
const int _kBackspaceIndex = 11;
const int _kUnlockIndex = 12;
const int _kCancelIndex = 13;
const int _kGridColumns = 3;

class _AppLockGateState extends State<AppLockGate> {
  late bool _locked = AppSettings.password.isNotEmpty;
  final TextEditingController _pinController = TextEditingController();
  String? _pinError;

  int _selectedIndex = 0;
  final FocusNode _gateFocusNode = FocusNode(debugLabel: 'appLockGate');

  @override
  void dispose() {
    _pinController.dispose();
    _gateFocusNode.dispose();
    super.dispose();
  }

  ////////////////////////////////////////////////////////////
  /// PIN EDITING — shared by keypad taps, Select-on-highlighted-tile,
  /// and direct physical-keyboard digit/backspace presses.
  ////////////////////////////////////////////////////////////

  void _appendDigit(String digit) {
    setState(() {
      _pinController.text += digit;
      _pinError = null;
    });
  }

  void _backspace() {
    final text = _pinController.text;
    if (text.isEmpty) return;
    setState(() {
      _pinController.text = text.substring(0, text.length - 1);
      _pinError = null;
    });
  }

  void _clear() {
    if (_pinController.text.isEmpty) return;
    setState(() {
      _pinController.clear();
      _pinError = null;
    });
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

  void _cancel() {
    Navigator.maybePop(context);
  }

  ////////////////////////////////////////////////////////////
  /// SELECTION / REMOTE NAVIGATION
  ////////////////////////////////////////////////////////////

  void _moveSelection(int newIndex) {
    if (newIndex < 0 || newIndex > _kCancelIndex) return;
    setState(() => _selectedIndex = newIndex);
  }

  void _activateSelected() {
    switch (_selectedIndex) {
      case _kClearIndex:
        _clear();
        break;
      case _kZeroIndex:
        _appendDigit('0');
        break;
      case _kBackspaceIndex:
        _backspace();
        break;
      case _kUnlockIndex:
        _attemptUnlock();
        break;
      case _kCancelIndex:
        _cancel();
        break;
      default:
        if (_selectedIndex >= 0 && _selectedIndex <= 8) {
          _appendDigit((_selectedIndex + 1).toString());
        }
    }
  }

  static final Map<LogicalKeyboardKey, String> _digitKeys = {
    LogicalKeyboardKey.digit0: '0',
    LogicalKeyboardKey.digit1: '1',
    LogicalKeyboardKey.digit2: '2',
    LogicalKeyboardKey.digit3: '3',
    LogicalKeyboardKey.digit4: '4',
    LogicalKeyboardKey.digit5: '5',
    LogicalKeyboardKey.digit6: '6',
    LogicalKeyboardKey.digit7: '7',
    LogicalKeyboardKey.digit8: '8',
    LogicalKeyboardKey.digit9: '9',
    LogicalKeyboardKey.numpad0: '0',
    LogicalKeyboardKey.numpad1: '1',
    LogicalKeyboardKey.numpad2: '2',
    LogicalKeyboardKey.numpad3: '3',
    LogicalKeyboardKey.numpad4: '4',
    LogicalKeyboardKey.numpad5: '5',
    LogicalKeyboardKey.numpad6: '6',
    LogicalKeyboardKey.numpad7: '7',
    LogicalKeyboardKey.numpad8: '8',
    LogicalKeyboardKey.numpad9: '9',
  };

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    // Physical/Bluetooth keyboard fast path: typing digits or Backspace
    // works no matter what's currently highlighted.
    final digit = _digitKeys[key];
    if (digit != null) {
      _appendDigit(digit);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace) {
      _backspace();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowRight) {
      if (_selectedIndex <= 8) {
        final col = _selectedIndex % _kGridColumns;
        if (col < _kGridColumns - 1) _moveSelection(_selectedIndex + 1);
      } else if (_selectedIndex >= _kClearIndex &&
          _selectedIndex <= _kBackspaceIndex) {
        if (_selectedIndex < _kBackspaceIndex) _moveSelection(_selectedIndex + 1);
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowLeft) {
      if (_selectedIndex <= 8) {
        final col = _selectedIndex % _kGridColumns;
        if (col > 0) _moveSelection(_selectedIndex - 1);
      } else if (_selectedIndex >= _kClearIndex &&
          _selectedIndex <= _kBackspaceIndex) {
        if (_selectedIndex > _kClearIndex) _moveSelection(_selectedIndex - 1);
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowDown) {
      if (_selectedIndex <= 8) {
        _moveSelection(_selectedIndex + _kGridColumns);
      } else if (_selectedIndex >= _kClearIndex &&
          _selectedIndex <= _kBackspaceIndex) {
        _moveSelection(_kUnlockIndex);
      } else if (_selectedIndex == _kUnlockIndex) {
        _moveSelection(_kCancelIndex);
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowUp) {
      if (_selectedIndex >= _kClearIndex && _selectedIndex <= _kBackspaceIndex) {
        _moveSelection(_selectedIndex - _kGridColumns);
      } else if (_selectedIndex >= 3 && _selectedIndex <= 8) {
        _moveSelection(_selectedIndex - _kGridColumns);
      } else if (_selectedIndex == _kUnlockIndex) {
        _moveSelection(_kZeroIndex);
      } else if (_selectedIndex == _kCancelIndex) {
        _moveSelection(_kUnlockIndex);
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.numpadEnter) {
      _activateSelected();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
      _cancel();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  ////////////////////////////////////////////////////////////
  /// BUILD
  ////////////////////////////////////////////////////////////

  @override
  Widget build(BuildContext context) {
    if (!_locked) return widget.child;

    return Focus(
      focusNode: _gateFocusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          // A fixed-height grid plus field plus two buttons can be taller
          // than the available height on some (especially TV/landscape)
          // screens. SingleChildScrollView is a safety net for that case —
          // touch/mouse can drag-scroll, and content still fits without
          // scrolling on most screens given the sizes below.
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 300),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock, size: 40, color: Colors.tealAccent),
                    const SizedBox(height: 8),
                    Text(
                      'Locked',
                      style: TextStyle(color: AppTheme.textPrimary, fontSize: 18),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _pinController,
                      obscureText: true,
                      readOnly: true,
                      showCursor: true,
                      style: TextStyle(color: AppTheme.textPrimary),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        errorText: _pinError,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildKeypad(),
                    const SizedBox(height: 12),
                    _actionTile(
                      index: _kUnlockIndex,
                      label: 'Unlock',
                      onTap: _attemptUnlock,
                      filled: true,
                    ),
                    const SizedBox(height: 8),
                    _actionTile(
                      index: _kCancelIndex,
                      label: 'Cancel',
                      onTap: _cancel,
                      filled: false,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildKeypad() {
    // Rows: [1 2 3] [4 5 6] [7 8 9] [Clear 0 Backspace]
    final tiles = <Widget>[
      for (var d = 1; d <= 9; d++) _keyTile(index: d - 1, label: '$d'),
      _keyTile(index: _kClearIndex, label: 'C', onTap: _clear),
      _keyTile(index: _kZeroIndex, label: '0'),
      _keyTile(
        index: _kBackspaceIndex,
        icon: Icons.backspace_outlined,
        onTap: _backspace,
      ),
    ];

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: _kGridColumns,
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      childAspectRatio: 1.8,
      children: tiles,
    );
  }

  Widget _keyTile({
    required int index,
    String? label,
    IconData? icon,
    VoidCallback? onTap,
  }) {
    final isSelected = _selectedIndex == index;
    final action = onTap ?? () => _appendDigit(label!);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          setState(() => _selectedIndex = index);
          action();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: isSelected ? Colors.teal.shade700 : AppTheme.panel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? Colors.tealAccent : Colors.transparent,
              width: 2,
            ),
          ),
          alignment: Alignment.center,
          child: icon != null
              ? Icon(
            icon,
            size: 20,
            color: isSelected ? Colors.white : AppTheme.textPrimary,
          )
              : Text(
            label!,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isSelected ? Colors.white : AppTheme.textPrimary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _actionTile({
    required int index,
    required String label,
    required VoidCallback onTap,
    required bool filled,
  }) {
    final isSelected = _selectedIndex == index;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          setState(() => _selectedIndex = index);
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: filled
                ? (isSelected ? Colors.teal.shade400 : Colors.teal.shade700)
                : (isSelected ? AppTheme.panel : Colors.transparent),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? Colors.tealAccent : Colors.transparent,
              width: 2,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: filled ? Colors.white : AppTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
