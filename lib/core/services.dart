// Copyright (c) 2026 ATC. All rights reserved.
// Proprietary and confidential. Use, copying, modification or distribution without
// written permission from ATC is prohibited. See LICENSE in the repository root.

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;

import 'bridges.dart';
import 'db.dart';
import 'models.dart';
import 'settings.dart';

/// Result of one access attempt, shown on the kiosk.
class AccessDecision {
  final bool granted;
  final String reason;
  final AppUser? user;
  final String method;
  final int? score;
  final String direction;
  final bool duplicate;
  final DateTime at;

  AccessDecision({
    required this.granted,
    required this.reason,
    this.user,
    required this.method,
    this.score,
    this.direction = '',
    this.duplicate = false,
    DateTime? at,
  }) : at = at ?? DateTime.now();
}

/// Applies access rules (status, validity window, schedule), logs, and notifies integrations.
class AccessEngine {
  AccessEngine._();
  static final instance = AccessEngine._();

  final _db = AppDb.instance;
  final _tts = FlutterTts();
  bool _ttsReady = false;

  /// Kiosk choice in attendance mode: 'auto', 'in' or 'out'.
  String directionChoice = 'auto';

  Future<AccessDecision> onPalm(String palmId, int score) async {
    final user = await _db.userByPalmId(palmId);
    if (user == null) {
      // The SDK library holds a template we have no record of: remove it (as the vendor demo does).
      unawaited(PalmBridge.instance.deleteFeature(palmId));
      return _record(AccessDecision(granted: false, reason: Reason.unknown, method: 'palm', score: score));
    }
    final method = palmId == user.leftPalmId ? 'palmLeft' : 'palmRight';
    return _evaluate(user, method, score);
  }

  Future<AccessDecision> onUnknownPalm(int score) =>
      _record(AccessDecision(granted: false, reason: Reason.unknown, method: 'palm', score: score));

  Future<AccessDecision> onQr(String text) async {
    final user = await _db.userByQr(text);
    if (user == null) {
      return _record(AccessDecision(granted: false, reason: Reason.unknownQr, method: 'qr'));
    }
    return _evaluate(user, 'qr', null);
  }

  Future<AccessDecision> _evaluate(AppUser user, String method, int? score) async {
    final now = DateTime.now();
    String reason = Reason.granted;
    if (user.status == UserStatus.suspended) {
      reason = Reason.suspended;
    } else if (user.validFrom != null && now.isBefore(user.validFrom!)) {
      reason = Reason.notYetValid;
    } else if (user.validUntil != null && now.isAfter(user.validUntil!)) {
      reason = Reason.expired;
    } else if (user.scheduleId != null && user.role != UserRole.admin) {
      final sch = await _db.scheduleById(user.scheduleId!);
      if (sch != null && !sch.allows(now)) reason = Reason.outsideSchedule;
    }
    final granted = reason == Reason.granted;

    var direction = '';
    var duplicate = false;
    if (granted) {
      final s = AppSettings.instance;
      final last = await _db.lastLogForUser(user.id!, since: DateTime(now.year, now.month, now.day));
      if (last != null && now.difference(last.ts).inSeconds < s.duplicateSeconds) {
        duplicate = true; // same person scanning twice: greet, but don't log again
        direction = last.direction;
      } else if (s.mode == TerminalMode.attendance) {
        direction = directionChoice == 'auto' ? ((last?.direction == 'in') ? 'out' : 'in') : directionChoice;
      }
    }
    final d = AccessDecision(
      granted: granted,
      reason: reason,
      user: user,
      method: method,
      score: score,
      direction: direction,
      duplicate: duplicate,
    );
    if (duplicate) {
      unawaited(WebhookService.instance.send(d)); // door must still open on a repeat scan
      return d;
    }
    return _record(d);
  }

  Future<AccessDecision> _record(AccessDecision d) async {
    await _db.insertLog(
      AccessLog(
        ts: d.at,
        userId: d.user?.id,
        userName: d.user?.name,
        userCode: d.user?.code,
        department: d.user?.departmentName,
        method: d.method,
        granted: d.granted,
        reason: d.reason,
        score: d.score,
        direction: d.direction,
      ),
    );
    unawaited(WebhookService.instance.send(d));
    return d;
  }

  /// LED, beep and voice feedback for a decision.
  Future<void> feedback(AccessDecision d) async {
    final s = AppSettings.instance;
    unawaited(PalmBridge.instance.led(d.granted ? 'green' : 'red'));
    if (s.beepEnabled) unawaited(DeviceBridge.instance.tone(d.granted ? 'granted' : 'denied'));
    if (s.voiceEnabled) {
      if (!_ttsReady) {
        _ttsReady = true;
        try {
          await _tts.setLanguage('en-US');
          await _tts.setSpeechRate(0.5);
        } catch (_) {}
      }
      final first = d.user?.name.split(' ').first ?? '';
      final text = d.granted ? (d.direction == 'out' ? 'Goodbye $first' : '${s.welcomeText} $first') : 'Access denied';
      try {
        await _tts.stop();
        unawaited(_tts.speak(text));
      } catch (_) {}
    }
  }
}

/// Keeps the SDK feature library in sync with the user table.
class PalmLibrary {
  PalmLibrary._();
  static final instance = PalmLibrary._();

  static String newPalmId(String hand) {
    final r = Random.secure();
    final hex = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    return '${hand == 'left' ? 'L' : 'R'}_$hex';
  }

  /// Registers a freshly captured template for [user] and stores it encrypted.
  Future<String?> saveTemplate(
    AppUser user,
    String hand,
    String palmId,
    String feature, {
    String actor = 'admin',
  }) async {
    final (ok, msg) = await PalmBridge.instance.addFeature(palmId, feature);
    if (!ok) return msg ?? 'The scanner rejected this template.';
    final token = await DeviceBridge.instance.encrypt(feature);
    final oldId = hand == 'left' ? user.leftPalmId : user.rightPalmId;
    if (hand == 'left') {
      user.leftPalmId = palmId;
      user.leftFeature = token;
    } else {
      user.rightPalmId = palmId;
      user.rightFeature = token;
    }
    await AppDb.instance.saveUser(user);
    if (oldId != null && oldId != palmId) await PalmBridge.instance.deleteFeature(oldId);
    await AppDb.instance.audit(actor, 'Palm enrolled', '${user.code} ${user.name} ($hand)');
    return null;
  }

  Future<void> removeTemplate(AppUser user, String hand, {String actor = 'admin'}) async {
    final id = hand == 'left' ? user.leftPalmId : user.rightPalmId;
    if (id != null) await PalmBridge.instance.deleteFeature(id);
    if (hand == 'left') {
      user.leftPalmId = null;
      user.leftFeature = null;
    } else {
      user.rightPalmId = null;
      user.rightFeature = null;
    }
    await AppDb.instance.saveUser(user);
    await AppDb.instance.audit(actor, 'Palm removed', '${user.code} ${user.name} ($hand)');
  }

  Future<void> deleteUser(AppUser user, {String actor = 'admin'}) async {
    for (final id in [user.leftPalmId, user.rightPalmId]) {
      if (id != null) await PalmBridge.instance.deleteFeature(id);
    }
    await AppDb.instance.deleteUser(user.id!);
    await AppDb.instance.audit(actor, 'User deleted', '${user.code} ${user.name}');
  }

  /// Rebuilds the SDK library from encrypted templates. Returns (restored, failed).
  Future<(int, int)> resync() async {
    await PalmBridge.instance.deleteAllFeatures();
    var ok = 0, fail = 0;
    for (final u in await AppDb.instance.enrolledUsersWithTemplates()) {
      for (final (id, token) in [(u.leftPalmId, u.leftFeature), (u.rightPalmId, u.rightFeature)]) {
        if (id == null || token == null) continue;
        try {
          final feature = await DeviceBridge.instance.decrypt(token);
          final (added, _) = await PalmBridge.instance.addFeature(id, feature);
          added ? ok++ : fail++;
        } catch (_) {
          fail++;
        }
      }
    }
    return (ok, fail);
  }

  /// Called after SDK init: if the library and the DB disagree, rebuild it.
  Future<void> verifyOnStartup() async {
    final count = await PalmBridge.instance.featureCount();
    final stats = await AppDb.instance.userStats();
    if (count >= 0 && count != (stats['palms'] ?? 0)) {
      final (ok, fail) = await resync();
      await AppDb.instance.audit(
        'system',
        'Palm library resynced',
        'sdk=$count db=${stats['palms']} ok=$ok fail=$fail',
      );
    }
  }
}

/// Posts signed JSON events to an HTTPS endpoint (door controller, HR/ERP, SIEM...).
class WebhookService {
  WebhookService._();
  static final instance = WebhookService._();

  static String? validateUrl(String url) {
    if (url.isEmpty) return null;
    final u = Uri.tryParse(url);
    if (u == null || !u.hasAuthority) return 'Enter a valid URL';
    if (u.scheme != 'https') return 'Only https:// URLs are allowed';
    return null;
  }

  Future<String?> send(AccessDecision d, {bool test = false}) async {
    final s = AppSettings.instance;
    if (s.webhookUrl.isEmpty || validateUrl(s.webhookUrl) != null) return 'Webhook not configured';
    if (!test && !d.granted && !s.webhookOnDenied) return null;
    final body = jsonEncode({
      'event': test ? 'test' : 'access',
      'terminal': s.terminalName,
      'company': s.companyName,
      'timestamp': d.at.toUtc().toIso8601String(),
      'granted': d.granted,
      'reason': d.reason,
      'method': d.method,
      'direction': d.direction,
      'duplicate': d.duplicate,
      if (d.score != null) 'score': d.score,
      if (d.user != null)
        'user': {
          'code': d.user!.code,
          'name': d.user!.name,
          'department': d.user!.departmentName,
          'role': d.user!.role.name,
        },
    });
    final ts = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final headers = {'Content-Type': 'application/json', 'X-ATC-Timestamp': ts};
    if (s.webhookSecret.isNotEmpty) {
      final secret = s.webhookSecret.startsWith('v1:')
          ? await DeviceBridge.instance.decrypt(s.webhookSecret)
          : s.webhookSecret;
      // Receiver verifies HMAC-SHA256(secret, "<timestamp>.<body>") to reject forged or replayed calls.
      headers['X-ATC-Signature'] = 'sha256=${await DeviceBridge.instance.hmac(secret, '$ts.$body')}';
    }
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final r = await http
            .post(Uri.parse(s.webhookUrl), headers: headers, body: body)
            .timeout(const Duration(seconds: 6));
        if (r.statusCode >= 200 && r.statusCode < 300) return null;
        if (attempt == 1) return 'HTTP ${r.statusCode}';
      } catch (e) {
        if (attempt == 1) {
          if (kDebugMode) debugPrint('webhook failed: $e');
          return e.toString();
        }
      }
    }
    return 'Failed';
  }
}
