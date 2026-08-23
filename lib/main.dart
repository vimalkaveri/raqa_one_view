import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/config/configuration_store.dart';
import 'services/rs485/rs485_service.dart';
import 'services/settings/app_settings.dart';

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
    // Loads sirenEnabled/priorityEnabled/password/pinSize/darkModeEnabled
    // from disk. darkModeNotifier already carries the default (dark) until
    // this resolves, so there's no flash of the wrong theme either way.
    AppSettings.loadSettings();
  }

  @override
  void dispose() {
    manager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppSettings.darkModeNotifier,
      builder: (context, darkModeEnabled, _) {
        return MaterialApp(
          title: 'Raqa One View',
          debugShowCheckedModeBanner: false,

          theme: ThemeData(
            brightness: Brightness.light,
            colorSchemeSeed: Colors.teal,
            useMaterial3: true,
            focusColor: Colors.teal,
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            colorSchemeSeed: Colors.teal,
            useMaterial3: true,
            focusColor: Colors.tealAccent,
          ),
          themeMode: darkModeEnabled ? ThemeMode.dark : ThemeMode.light,

          home: HomeScreen(
            manager: manager,
          ),
        );
      },
    );
  }
}