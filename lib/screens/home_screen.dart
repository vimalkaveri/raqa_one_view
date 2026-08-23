import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/rs485/rs485_service.dart';
import '../utils/app_theme.dart';
import '../utils/menu_item.dart';
import '../widgets/tv_card.dart';
import 'config/config_page.dart';
import 'dashboard/dashboard_page.dart';
import 'scane/device_screen.dart';
import 'setting/setting_page.dart';

class HomeScreen extends StatefulWidget {
  final Rs485Service manager;

  const HomeScreen({
    super.key,
    required this.manager,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const int itemCount = 4;

  int _selectedIndex = 0;

  // Guards against double Navigator.push when the remote fires multiple
  // "select" key events before the first push completes.
  bool _isNavigating = false;

  final List<FocusNode> _focusNodes = List.generate(
    itemCount,
        (i) => FocusNode(debugLabel: 'menuCard$i'),
  );

  // Built once in initState rather than recomputed on every build — the
  // screenBuilder closures only depend on widget.manager, which is stable
  // for the lifetime of this State.
  late final List<MenuItem> _menuItems = [
    MenuItem(
      icon: Icons.dashboard,
      label: 'Dashboard',
      screenBuilder: (context) => DashboardScreen(manager: widget.manager),
    ),
    MenuItem(
      icon: Icons.devices_other,
      label: 'Devices',
      screenBuilder: (context) => DeviceScreen(manager: widget.manager),
    ),
    MenuItem(
      icon: Icons.settings_input_component,
      label: 'Configuration',
      screenBuilder: (context) => ConfigScreen(),
    ),
    MenuItem(
      icon: Icons.settings,
      label: 'Settings',
      screenBuilder: (context) => const SettingScreen(),
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusSelectedCard();
    });
  }

  @override
  void dispose() {
    for (final node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _focusSelectedCard() {
    if (_selectedIndex < 0 || _selectedIndex >= _focusNodes.length) return;
    _focusNodes[_selectedIndex].requestFocus();
  }

  void _moveSelection(int newIndex) {
    if (newIndex < 0 || newIndex >= itemCount) return;
    setState(() => _selectedIndex = newIndex);
    _focusSelectedCard();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.arrowRight) {
      _moveSelection(_selectedIndex + 1);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowLeft) {
      _moveSelection(_selectedIndex - 1);
      return KeyEventResult.handled;
    }

    // Single-row grid: up/down have nowhere to go, but we still consume
    // the event so it doesn't leak to a parent scrollable/focus scope.
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.numpadEnter) {
      _openSelectedScreen();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack) {
      Navigator.maybePop(context);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  Future<void> _openSelectedScreen() async {
    if (_isNavigating) return;
    _isNavigating = true;

    final item = _menuItems[_selectedIndex];

    try {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: item.screenBuilder),
      );
    } finally {
      _isNavigating = false;
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _focusSelectedCard();
        });
      }
    }
  }

  void _onCardTap(int index) {
    setState(() => _selectedIndex = index);
    _openSelectedScreen();
  }

  void _onCardFocus(int index) {
    if (_selectedIndex != index) {
      setState(() => _selectedIndex = index);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 48,
              vertical: 32,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'RaQa One View',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Real-Time Fire & Safety Monitoring System',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 40),
                Expanded(child: _buildMenuGrid()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMenuGrid() {
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 24,
        mainAxisSpacing: 24,
        childAspectRatio: 1.3,
      ),
      itemCount: _menuItems.length,
      itemBuilder: (context, index) {
        final item = _menuItems[index];
        return TvCard(
          key: ValueKey(item.label),
          focusNode: _focusNodes[index],
          icon: item.icon,
          label: item.label,
          selected: _selectedIndex == index,
          onTap: () => _onCardTap(index),
          onFocus: () => _onCardFocus(index),
        );
      },
    );
  }
}