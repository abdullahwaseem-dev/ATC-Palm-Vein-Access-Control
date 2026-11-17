// Copyright (c) 2026 ATC. All rights reserved.
// Proprietary and confidential. Use, copying, modification or distribution without
// written permission from ATC is prohibited. See LICENSE in the repository root.

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'bridges.dart';
import 'db.dart';
import 'settings.dart';

/// Admin authentication: Keystore-peppered PIN hash, escalating lockout,
/// and an inactivity timeout that returns the terminal to kiosk mode.
class AuthService extends ChangeNotifier {
  AuthService._();
  static final instance = AuthService._();

  String? _actor;
  DateTime _lastActivity = DateTime.now();
  Timer? _timer;
  VoidCallback? onSessionExpired;

  bool get isLoggedIn => _actor != null;
  String get actor => _actor ?? 'system';

  static bool isValidPin(String pin) {
    if (!RegExp(r'^\d{6,8}$').hasMatch(pin)) return false;
    if (RegExp(r'^(\d)\1+$').hasMatch(pin)) return false; // 000000
    const seq = '01234567890';
    const rev = '09876543210';
    if (seq.contains(pin) || rev.contains(pin)) return false; // 123456, 654321
    return true;
  }

  Future<void> setPin(String pin, {String by = 'setup'}) async {
    final hash = await DeviceBridge.instance.hashPin(pin);
    await AppSettings.instance.setMany({'admin_pin_hash': hash, 'failed_pin_count': 0, 'lockout_until': 0});
    await AppDb.instance.audit(by, 'Admin PIN changed');
  }

  /// Remaining lockout, or null when PIN entry is allowed.
  Duration? lockoutRemaining() {
    final until = AppSettings.instance.lockoutUntil;
    final now = DateTime.now().millisecondsSinceEpoch;
    return until > now ? Duration(milliseconds: until - now) : null;
  }

  /// Returns null on success, otherwise an error message.
  Future<String?> loginWithPin(String pin) async {
    final s = AppSettings.instance;
    final lock = lockoutRemaining();
    if (lock != null) return 'Locked. Try again in ${lock.inSeconds + 1}s.';
    final ok = await DeviceBridge.instance.verifyPin(pin, s.adminPinHash);
    if (ok) {
      await s.setMany({'failed_pin_count': 0, 'lockout_until': 0});
      _start('Administrator (PIN)');
      await AppDb.instance.audit(actor, 'Admin login', 'method=PIN');
      return null;
    }
    final fails = s.failedPinCount + 1;
    final updates = <String, Object>{'failed_pin_count': fails};
    String msg = 'Incorrect PIN.';
    if (fails >= s.maxPinAttempts) {
      // 30s, 60s, 120s ... capped at 15 minutes.
      final secs = min(900, 30 * pow(2, fails - s.maxPinAttempts).toInt());
      updates['lockout_until'] = DateTime.now().millisecondsSinceEpoch + secs * 1000;
      msg = 'Too many attempts. Locked for ${secs}s.';
    } else {
      msg = 'Incorrect PIN. ${s.maxPinAttempts - fails} attempt(s) left.';
    }
    await s.setMany(updates);
    await AppDb.instance.audit('unknown', 'Failed admin login', 'attempt=$fails');
    return msg;
  }

  Future<void> loginWithPalm(String adminName) async {
    _start(adminName);
    await AppDb.instance.audit(actor, 'Admin login', 'method=palm');
  }

  void _start(String who) {
    _actor = who;
    _lastActivity = DateTime.now();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _check());
    notifyListeners();
  }

  void touch() => _lastActivity = DateTime.now();

  /// Pause the timeout during long operations (enrollment, calibration, backup).
  bool _paused = false;
  void pauseTimeout(bool paused) {
    _paused = paused;
    touch();
  }

  void _check() {
    if (_actor == null) return;
    // A paused timeout (enrollment, backup) is still capped so an abandoned screen locks eventually.
    final limit = _paused ? const Duration(minutes: 10) : Duration(minutes: AppSettings.instance.autoLockMinutes);
    if (DateTime.now().difference(_lastActivity) > limit) {
      logout(reason: 'timeout');
      onSessionExpired?.call();
    }
  }

  Future<void> logout({String reason = 'manual'}) async {
    if (_actor == null) return;
    await AppDb.instance.audit(actor, 'Admin logout', 'reason=$reason');
    _actor = null;
    _timer?.cancel();
    notifyListeners();
  }
}
