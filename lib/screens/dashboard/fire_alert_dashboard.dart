import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/config/site_image_config.dart';
import '../../utils/app_theme.dart';

/// Layout-only widget for the Fire Alert dashboard.
///
/// Fire detection/state is owned by DashboardScreen. This widget only
/// renders the alert-state composition and reports floor selection back
/// through [onFloorSelected].
class FireAlertDashboardView extends StatelessWidget {
  final Widget topStatusBar;
  final List<SiteImageConfig> fireFloors;
  final int selectedFloorIndex;
  final int focusedFloorIndex;
  final ValueChanged<int> onFloorSelected;
  final ValueChanged<int> onFloorFocused;
  final ValueChanged<int> onFloorMove;
  final List<FocusNode> floorFocusNodes;
  final SiteImageConfig selectedFloor;
  final Widget floorBody;
  final Widget alertDeviceDetails;

  const FireAlertDashboardView({
    super.key,
    required this.topStatusBar,
    required this.fireFloors,
    required this.selectedFloorIndex,
    required this.focusedFloorIndex,
    required this.onFloorSelected,
    required this.onFloorFocused,
    required this.onFloorMove,
    required this.floorFocusNodes,
    required this.selectedFloor,
    required this.floorBody,
    required this.alertDeviceDetails,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        topStatusBar,
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _FireFloorList(
                floors: fireFloors,
                selectedIndex: selectedFloorIndex,
                focusedIndex: focusedFloorIndex,
                floorFocusNodes: floorFocusNodes,
                onSelected: onFloorSelected,
                onFocused: onFloorFocused,
                onMove: onFloorMove,
              ),
              Expanded(
                child: Column(
                  children: [
                    Container(
                      height: 44,
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      alignment: Alignment.centerLeft,
                      decoration: BoxDecoration(
                        color: AppTheme.card,
                        border: const Border(
                          bottom: BorderSide(color: Colors.redAccent),
                        ),
                      ),
                      child: Text(
                        '${selectedFloor.floorLabel} image',
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Expanded(child: floorBody),
                  ],
                ),
              ),
            ],
          ),
        ),
        alertDeviceDetails,
      ],
    );
  }
}

class _FireFloorList extends StatelessWidget {
  final List<SiteImageConfig> floors;
  final int selectedIndex;
  final int focusedIndex;
  final List<FocusNode> floorFocusNodes;
  final ValueChanged<int> onSelected;
  final ValueChanged<int> onFocused;
  final ValueChanged<int> onMove;

  const _FireFloorList({
    required this.floors,
    required this.selectedIndex,
    required this.focusedIndex,
    required this.floorFocusNodes,
    required this.onSelected,
    required this.onFocused,
    required this.onMove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 190,
      color: const Color(0xFF200404),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 14, 12, 8),
            child: Text(
              'Fire Floor',
              style: TextStyle(
                color: Colors.redAccent,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: floors.length,
              itemBuilder: (context, index) {
                final floor = floors[index];
                final selected = index == selectedIndex;
                final focused = index == focusedIndex;

                return Focus(
                  focusNode: index < floorFocusNodes.length
                      ? floorFocusNodes[index]
                      : null,
                  onFocusChange: (hasFocus) {
                    if (hasFocus) {
                      onFocused(index);
                    }
                  },
                  onKeyEvent: (node, event) {
                    if (event is! KeyDownEvent) {
                      return KeyEventResult.ignored;
                    }

                    final key = event.logicalKey;

                    if (key == LogicalKeyboardKey.enter ||
                        key == LogicalKeyboardKey.select ||
                        key == LogicalKeyboardKey.numpadEnter) {
                      onSelected(index);
                      return KeyEventResult.handled;
                    }

                    if (key == LogicalKeyboardKey.arrowDown) {
                      if (index < floors.length - 1) {
                        onMove(index + 1);
                      }
                      return KeyEventResult.handled;
                    }

                    if (key == LogicalKeyboardKey.arrowUp) {
                      if (index > 0) {
                        onMove(index - 1);
                      }
                      return KeyEventResult.handled;
                    }

                    return KeyEventResult.ignored;
                  },
                  child: InkWell(
                    onTap: () => onSelected(index),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      alignment: Alignment.centerLeft,
                      decoration: BoxDecoration(
                        color: selected
                            ? Colors.red.withOpacity(0.12)
                            : focused
                                ? Colors.white.withOpacity(0.08)
                                : Colors.transparent,
                        border: Border(
                          left: BorderSide(
                            color: selected || focused
                                ? Colors.redAccent
                                : Colors.transparent,
                            width: 3,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.local_fire_department,
                            color: Colors.redAccent,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              floor.floorLabel,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: selected || focused
                                    ? AppTheme.textPrimary
                                    : AppTheme.textSecondary,
                                fontWeight: selected || focused
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
