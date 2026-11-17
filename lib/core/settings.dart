// Copyright (c) 2026 ATC. All rights reserved.
// Proprietary and confidential. Use, copying, modification or distribution without
// written permission from ATC is prohibited. See LICENSE in the repository root.

import 'package:flutter/foundation.dart';

import 'bridges.dart';
import 'db.dart';

enum TerminalMode { access, attendance }

/// Typed, persisted application settings (stored in the app-private SQLite DB).
class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final instance = AppSettings._();

  final Map<String, String> _v = {};

  Future<void> load() async {
    _v
      ..clear()
      ..addAll(await AppDb.instance.allSettings());
    notifyListeners();
  }

  String _s(String k, String d) => _v[k] ?? d;
  int _i(String k, int d) => int.tryParse(_v[k] ?? '') ?? d;
  bool _b(String k, bool d) => _v.containsKey(k) ? _v[k] == '1' : d;

  Future<void> set(String key, Object value) async {
    final s = value is bool ? (value ? '1' : '0') : value.toString();
    _v[key] = s;
    await AppDb.instance.putSetting(key, s);
    notifyListeners();
  }

  Future<void> setMany(Map<String, Object> values) async {
    for (final e in values.entries) {
      final s = e.value is bool ? ((e.value as bool) ? '1' : '0') : e.value.toString();
      _v[e.key] = s;
      await AppDb.instance.putSetting(e.key, s);
    }
    notifyListeners();
  }

  // ---- setup / identity
  bool get setupDone => _b('setup_done', false);
  String get companyName => _s('company_name', 'ATC');
  String get terminalName => _s('terminal_name', 'Main Entrance');
  String get welcomeText => _s('welcome_text', 'Welcome');

  // ---- terminal behaviour
  TerminalMode get mode => _s('mode', 'access') == 'attendance' ? TerminalMode.attendance : TerminalMode.access;
  int get resultSeconds => _i('result_seconds', 3);
  int get duplicateSeconds => _i('duplicate_seconds', 30);
  bool get voiceEnabled => _b('voice', true);
  bool get beepEnabled => _b('beep', true);
  bool get showPhoto => _b('show_photo', true);
  bool get privacyNames => _b('privacy_names', false); // show first name only on kiosk
  bool get showScore => _b('show_score', false);

  // ---- recognition / camera
  int get threshold => _i('threshold', 65);
  bool get qrEnabled => _b('qr_enabled', false);
  int get irVid => _i('ir_vid', 0x1D6C);
  int get irPid => _i('ir_pid', 0x0103);
  int get rgbVid => _i('rgb_vid', 0x2C7F);
  int get rgbPid => _i('rgb_pid', 0x4A60);
  int get rotation => _i('rotation', 270);
  bool get mirrorH => _b('mirror_h', false);
  bool get mirrorV => _b('mirror_v', true);

  // ---- security
  String get adminPinHash => _s('admin_pin_hash', '');
  int get autoLockMinutes => _i('auto_lock_minutes', 3);
  int get maxPinAttempts => _i('max_pin_attempts', 5);
  bool get adminPalmUnlock => _b('admin_palm_unlock', true);
  bool get kioskLock => _b('kiosk_lock', false);
  bool get bootStart => _b('boot_start', false);
  int get failedPinCount => _i('failed_pin_count', 0);
  int get lockoutUntil => _i('lockout_until', 0);

  // ---- integration
  String get webhookUrl => _s('webhook_url', '');
  String get webhookSecret => _s('webhook_secret', '');
  bool get webhookOnDenied => _b('webhook_denied', true);

  // ---- data
  int get logRetentionDays => _i('log_retention_days', 365);

  Future<void> applyToEngine() => PalmBridge.instance.configure(
    threshold: threshold,
    irVid: irVid,
    irPid: irPid,
    rgbVid: rgbVid,
    rgbPid: rgbPid,
    rotation: rotation,
    mirrorH: mirrorH,
    mirrorV: mirrorV,
    qrEnabled: qrEnabled,
  );

  /// Settings that are safe to put in a backup (no PIN hash, lockout state or secrets).
  Map<String, String> exportable() => Map.fromEntries(
    _v.entries.where(
      (e) => !const {
        'admin_pin_hash',
        'failed_pin_count',
        'lockout_until',
        'webhook_secret',
        'setup_done',
      }.contains(e.key),
    ),
  );
}
