import 'package:flutter/cupertino.dart';

class MenuItem {
  final IconData icon;
  final String label;
  final Widget Function(BuildContext context) screenBuilder;

  const MenuItem({
    required this.icon,
    required this.label,
    required this.screenBuilder,
  });
}