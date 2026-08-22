import 'package:flutter/material.dart';

import '../../services/config/site_image_config.dart';

/// Layout-only widget for the Normal dashboard.
///
/// Business logic remains in DashboardScreen; this file only owns the
/// composition of the normal-state UI.
class NormalDashboardView extends StatelessWidget {
  final Widget topStatusBar;
  final Widget leftPanel;
  final Widget floorBody;
  final Widget rightPanel;
  final Widget bottomSummary;
  final Widget emptyState;
  final bool hasFloors;

  const NormalDashboardView({
    super.key,
    required this.topStatusBar,
    required this.leftPanel,
    required this.floorBody,
    required this.rightPanel,
    required this.bottomSummary,
    required this.emptyState,
    required this.hasFloors,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        topStatusBar,
        Expanded(
          child: hasFloors
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    leftPanel,
                    Expanded(
                      child: Column(
                        children: [
                          Expanded(child: floorBody),
                        ],
                      ),
                    ),
                    rightPanel,
                  ],
                )
              : emptyState,
        ),
        if (hasFloors) bottomSummary,
      ],
    );
  }
}
