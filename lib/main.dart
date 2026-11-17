// Copyright (c) 2026 ATC. All rights reserved.
// Proprietary and confidential. Use, copying, modification or distribution without
// written permission from ATC is prohibited. See LICENSE in the repository root.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/app_state.dart';
import 'core/auth.dart';
import 'core/db.dart';
import 'core/settings.dart';
import 'screens/kiosk_screen.dart';
import 'screens/setup_wizard.dart';
import 'widgets/common.dart';

final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Release builds print errors as "Instance of DiagnosticsProperty"; log the app frames instead.
  FlutterError.onError = (details) {
    final frames = (details.stack?.toString() ?? '')
        .split('\n')
        .where((l) => l.contains('package:atc_palm_access'))
        .take(8)
        .join(' <- ');
    debugPrint('APP-ERROR ${details.exception} :: ${details.library} :: $frames');
  };
  await AppDb.instance.open();
  await AppSettings.instance.load();
  await AppState.instance.start();
  AuthService.instance.onSessionExpired = () {
    // Inactivity timeout: drop back to the terminal screen.
    navigatorKey.currentState?.popUntil((r) => r.isFirst);
  };
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const PalmAccessApp());
}

class PalmAccessApp extends StatelessWidget {
  const PalmAccessApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ATC Palm Access',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      navigatorObservers: [routeObserver],
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ThemeMode.light,
      home: AppSettings.instance.setupDone ? const KioskScreen() : const SetupWizard(),
      builder: (context, child) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => AuthService.instance.touch(),
        child: child,
      ),
    );
  }
}
