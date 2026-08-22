import 'package:flutter/material.dart';

import '../../services/config/site_image_config.dart';

/// Layout-only widget for the Fire Alert dashboard.
///
/// Fire detection/state is owned by DashboardScreen. This widget only
/// renders the alert-state composition and reports floor selection back
/// through [onFloorSelected].
class FireAlertDashboardView extends StatelessWidget {
  final Widget topStatusBar;
  final List<SiteImageConfig> fireFloors;
  final int selectedFloorIndex;
  final ValueChanged<int> onFloorSelected;
  final SiteImageConfig selectedFloor;
  final Widget floorBody;
  final Widget alertDeviceDetails;

  const FireAlertDashboardView({
    super.key,
    required this.topStatusBar,
    required this.fireFloors,
    required this.selectedFloorIndex,
    required this.onFloorSelected,
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
                onSelected: onFloorSelected,
              ),
              Expanded(
                child: Column(
                  children: [
                    Container(
                      height: 44,
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      alignment: Alignment.centerLeft,
                      decoration: const BoxDecoration(
                        color: Color(0xFF121212),
                        border: Border(
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
  final ValueChanged<int> onSelected;

  const _FireFloorList({
    required this.floors,
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 190,
      color: const Color(0xFF161616),
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

                return InkWell(
                  onTap: () => onSelected(index),
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(
                      color: selected
                          ? Colors.red.withOpacity(0.12)
                          : Colors.transparent,
                      border: Border(
                        left: BorderSide(
                          color: selected
                              ? Colors.redAccent
                              : Colors.transparent,
                          width: 3,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
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
                              color: selected ? Colors.white : Colors.white54,
                              fontWeight: selected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
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
