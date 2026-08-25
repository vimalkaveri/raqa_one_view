import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'screens/dashboard/dashboard_page.dart';
import 'screens/home_screen.dart';
import 'services/config/configuration_store.dart';
import 'services/rs485/rs485_service.dart';
import 'services/settings/app_settings.dart';

void main() {
  runApp(const RaqaOneViewApp());
}

/// Default [ScrollBehavior] only allows drag-to-scroll from touch/stylus/
/// trackpad. On Android (and other non-desktop targets) that silently
/// excludes a physical mouse, so any horizontal list — e.g. the fire-alert
/// device cards at the bottom of the dashboard — can be driven by the
/// remote (which scrolls programmatically via focus changes) but not by a
/// connected mouse. Adding [PointerDeviceKind.mouse] here fixes that for
/// every scrollable in the app.
class AppScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
        PointerDeviceKind.trackpad,
      };
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
          scrollBehavior: AppScrollBehavior(),

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

          // Skip the menu on launch if a site image is already configured
          // (saved from a previous session) — jump straight to the
          // Dashboard instead. ConfigurationStore.loadFromDisk() (kicked
          // off in initState) is async, so this listens for its
          // notifyListeners() call and re-decides once the saved config
          // (if any) has finished loading.
          home: AnimatedBuilder(
            animation: ConfigurationStore.instance,
            builder: (context, _) {
              final isConfigured = ConfigurationStore.instance.active != null;
              return isConfigured
                  ? DashboardScreen(manager: manager)
                  : HomeScreen(manager: manager);
            },
          ),
        );
      },
    );
  }
}