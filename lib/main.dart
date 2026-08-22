import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/config/configuration_store.dart';
import 'services/rs485/rs485_service.dart';

void main() {
  runApp(const RaqaOneViewApp());
}

class RaqaOneViewApp extends StatefulWidget {
  const RaqaOneViewApp({super.key});

  @override
  State<RaqaOneViewApp> createState() => _RaqaOneViewAppState();
}

class _RaqaOneViewAppState extends State<RaqaOneViewApp> {
  late final Rs485Service manager;

  @override
  void initState() {
    super.initState();

    manager = Rs485Service(
      onStateChanged: () {
        if (mounted) {
          setState(() {});
        }
      },
    );

    manager.init();
    ConfigurationStore.instance.loadFromDisk();
  }

  @override
  void dispose() {
    manager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Raqa One View',
      debugShowCheckedModeBanner: false,

      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.teal,
        useMaterial3: true,
        focusColor: Colors.tealAccent,
      ),

      home: HomeScreen(
        manager: manager,
      ),
    );
  }
}