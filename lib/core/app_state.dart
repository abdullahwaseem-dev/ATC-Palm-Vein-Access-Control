// Copyright (c) 2026 ATC. All rights reserved.
// Proprietary and confidential. Use, copying, modification or distribution without
// written permission from ATC is prohibited. See LICENSE in the repository root.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'bridges.dart';
import 'db.dart';
import 'services.dart';
import 'settings.dart';

/// Live scanner status shared across screens.
class AppState extends ChangeNotifier {
  AppState._();
  static final instance = AppState._();

  String initState = 'idle'; // idle | initializing | ready | no_device | unauthorized | error
  String? initMessage;
  bool irAttached = false;
  bool rgbAttached = false;
  StreamSubscription<PalmEvent>? _sub;
  Timer? _maintenance;

  bool get ready => initState == 'ready';

  String get statusLabel => switch (initState) {
    'ready' => 'Scanner ready',
    'initializing' => 'Starting scanner…',
    'no_device' => 'Palm module not connected',
    'unauthorized' => 'Scanner licence not activated',
    'error' => 'Scanner error',
    _ => 'Scanner idle',
  };

  Future<void> start() async {
    _sub ??= PalmBridge.instance.events.listen(_onEvent);
    try {
      final s = await PalmBridge.instance.status();
      initState = s['initState'] as String? ?? initState;
      initMessage = s['initMessage'] as String?;
      irAttached = s['irAttached'] == true;
      rgbAttached = s['rgbAttached'] == true;
      notifyListeners();
    } catch (_) {}
    await AppSettings.instance.applyToEngine();
    _maintenance ??= Timer.periodic(const Duration(hours: 6), (_) => runMaintenance());
    unawaited(runMaintenance());
  }

  void _onEvent(PalmEvent e) {
    if (e.type == 'init') {
      final prev = initState;
      initState = e.data['state'] as String;
      initMessage = e.data['message'] as String?;
      if (initState == 'ready' && prev != 'ready') {
        unawaited(PalmLibrary.instance.verifyOnStartup());
      }
      notifyListeners();
    } else if (e.type == 'camera') {
      irAttached = e.data['ir'] == true;
      rgbAttached = e.data['rgb'] == true;
      notifyListeners();
    }
  }

  /// Applies data-retention policy (logs, audit trail).
  Future<void> runMaintenance() async {
    final days = AppSettings.instance.logRetentionDays;
    if (days > 0) {
      final n = await AppDb.instance.purgeLogsOlderThan(days);
      if (n > 0) await AppDb.instance.audit('system', 'Retention purge', '$n access records older than $days days');
    }
    await AppDb.instance.purgeAuditOlderThan(730); // audit trail kept 2 years
  }
}
