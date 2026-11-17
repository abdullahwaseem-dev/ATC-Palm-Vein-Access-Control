// Copyright (c) 2026 ATC. All rights reserved.
// Proprietary and confidential. Use, copying, modification or distribution without
// written permission from ATC is prohibited. See LICENSE in the repository root.

import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

import 'bridges.dart';
import 'db.dart';
import 'models.dart';
import 'settings.dart';

/// Encrypted, portable backups (AES-256-GCM, key from PBKDF2 of an admin password),
/// plus CSV exports. Files are written through the Android system file picker only.
class BackupService {
  BackupService._();
  static final instance = BackupService._();

  static String? validatePassword(String p) {
    if (p.length < 10) return 'Use at least 10 characters';
    if (!RegExp(r'[A-Za-z]').hasMatch(p) || !RegExp(r'\d').hasMatch(p)) return 'Mix letters and numbers';
    return null;
  }

  /// Returns a message describing the outcome, or null if the user cancelled.
  Future<String?> exportBackup(String password, {bool includeLogs = true, required String actor}) async {
    final db = AppDb.instance;
    final users = await db.users();
    final userJson = <Map<String, Object?>>[];
    for (final u in users) {
      final m = u.toMap();
      // Re-key templates: decrypt from this device's Keystore so they can be restored on a replacement terminal.
      m['left_feature'] = u.leftFeature == null ? null : await DeviceBridge.instance.decrypt(u.leftFeature!);
      m['right_feature'] = u.rightFeature == null ? null : await DeviceBridge.instance.decrypt(u.rightFeature!);
      m.remove('photo'); // photos stay on the device
      userJson.add(m);
    }
    final payload = jsonEncode({
      'app': 'atc_palm_access',
      'schema': 1,
      'created': DateTime.now().toUtc().toIso8601String(),
      'terminal': AppSettings.instance.terminalName,
      'departments': (await db.departments()).map((d) => d.toMap()).toList(),
      'schedules': (await db.schedules()).map((s) => s.toMap()).toList(),
      'users': userJson,
      'settings': AppSettings.instance.exportable(),
      if (includeLogs) 'logs': (await db.logs(limit: 1000000)).map((l) => l.toMap()).toList(),
    });
    final enc = await DeviceBridge.instance.encryptBackup(payload, password);
    final name = 'atc-palm-backup-${DateFormat('yyyyMMdd-HHmm').format(DateTime.now())}.atcbak';
    final uri = await FilePicker.saveFile(
      fileName: name,
      bytes: Uint8List.fromList(utf8.encode(enc)),
      mimeType: 'application/octet-stream',
    );
    if (uri == null) return null;
    await db.audit(actor, 'Backup exported', '${users.length} users, logs=$includeLogs');
    return 'Backup saved (${users.length} users).';
  }

  /// Picks a backup file and returns its decrypted content, or throws on a wrong password.
  Future<Map<String, dynamic>?> readBackup(String password) async {
    final files = await FilePicker.pickFiles(type: FileType.any);
    if (files.isEmpty) return null;
    final text = utf8.decode(await files.first.readAsBytes());
    final env = jsonDecode(text) as Map<String, dynamic>;
    if (env['format'] != 'atc-palm-backup') throw const FormatException('Not an ATC Palm Access backup file');
    final plain = await DeviceBridge.instance.decryptBackup(
      salt: env['salt'] as String,
      iv: env['iv'] as String,
      data: env['data'] as String,
      iterations: env['iterations'] as int,
      password: password,
    );
    final data = jsonDecode(plain) as Map<String, dynamic>;
    if (data['app'] != 'atc_palm_access') throw const FormatException('Unsupported backup');
    return data;
  }

  /// Replaces all local data with the backup content. Returns a summary.
  Future<String> restore(Map<String, dynamic> data, {required String actor}) async {
    final db = AppDb.instance;
    final pinHash = AppSettings.instance.adminPinHash;
    final secret = AppSettings.instance.webhookSecret;
    await PalmBridge.instance.deleteAllFeatures();
    var palms = 0, failed = 0;
    await db.db.transaction((t) async {
      for (final table in ['access_logs', 'users', 'departments', 'schedules']) {
        await t.delete(table);
      }
      for (final d in (data['departments'] as List)) {
        await t.insert('departments', Map<String, Object?>.from(d as Map));
      }
      for (final s in (data['schedules'] as List)) {
        await t.insert('schedules', Map<String, Object?>.from(s as Map));
      }
      for (final l in (data['logs'] as List? ?? const [])) {
        await t.insert('access_logs', Map<String, Object?>.from(l as Map));
      }
    });
    for (final raw in (data['users'] as List)) {
      final m = Map<String, Object?>.from(raw as Map);
      final lf = m['left_feature'] as String?;
      final rf = m['right_feature'] as String?;
      final u = AppUser.fromMap(m);
      u.leftFeature = null;
      u.rightFeature = null;
      for (final (hand, id, f) in [('left', u.leftPalmId, lf), ('right', u.rightPalmId, rf)]) {
        if (id == null || f == null) {
          _clearId(u, hand);
          continue;
        }
        final (ok, _) = await PalmBridge.instance.addFeature(id, f);
        if (ok) {
          final token = await DeviceBridge.instance.encrypt(f);
          if (hand == 'left') {
            u.leftFeature = token;
          } else {
            u.rightFeature = token;
          }
          palms++;
        } else {
          _clearId(u, hand);
          failed++;
        }
      }
      await db.db.insert('users', u.toMap());
    }
    final settings = Map<String, Object>.from(data['settings'] as Map? ?? {});
    settings['admin_pin_hash'] = pinHash; // keep this device's PIN
    settings['webhook_secret'] = secret;
    settings['setup_done'] = true;
    await AppSettings.instance.setMany(settings);
    await AppSettings.instance.applyToEngine();
    final n = (data['users'] as List).length;
    await db.audit(actor, 'Backup restored', '$n users, $palms palms, $failed failed');
    return 'Restored $n users and $palms palm templates${failed > 0 ? ' ($failed could not be re-registered)' : ''}.';
  }

  static void _clearId(AppUser u, String hand) {
    if (hand == 'left') {
      u.leftPalmId = null;
    } else {
      u.rightPalmId = null;
    }
  }

  static String _csv(Object? v) {
    final s = v?.toString() ?? '';
    // Neutralise spreadsheet formula injection (=, +, -, @) and quote everything.
    final safe = RegExp(r'^[=+\-@\t\r]').hasMatch(s) ? "'$s" : s;
    return '"${safe.replaceAll('"', '""')}"';
  }

  Future<bool> _save(String name, List<List<Object?>> rows) async {
    final csv = '﻿${rows.map((r) => r.map(_csv).join(',')).join('\r\n')}';
    final uri = await FilePicker.saveFile(
      fileName: name,
      bytes: Uint8List.fromList(utf8.encode(csv)),
      mimeType: 'text/csv',
    );
    return uri != null;
  }

  Future<bool> exportLogsCsv(List<AccessLog> logs, {required String actor}) async {
    final f = DateFormat('yyyy-MM-dd HH:mm:ss');
    final ok = await _save('access-log-${DateFormat('yyyyMMdd-HHmm').format(DateTime.now())}.csv', [
      ['Time', 'Result', 'Reason', 'Direction', 'Employee ID', 'Name', 'Department', 'Method', 'Score'],
      for (final l in logs)
        [
          f.format(l.ts),
          l.granted ? 'Granted' : 'Denied',
          Reason.label(l.reason),
          l.direction,
          l.userCode,
          l.userName,
          l.department,
          methodLabel(l.method),
          l.score,
        ],
    ]);
    if (ok) await AppDb.instance.audit(actor, 'Access log exported', '${logs.length} rows');
    return ok;
  }

  Future<bool> exportAttendanceCsv(List<AttendanceDay> rows, {required String actor}) async {
    final d = DateFormat('yyyy-MM-dd');
    final t = DateFormat('HH:mm');
    String dur(Duration? x) => x == null ? '' : '${x.inHours}:${(x.inMinutes % 60).toString().padLeft(2, '0')}';
    final ok = await _save('attendance-${DateFormat('yyyyMMdd-HHmm').format(DateTime.now())}.csv', [
      ['Date', 'Employee ID', 'Name', 'Department', 'First in', 'Last out', 'Hours', 'Scans'],
      for (final r in rows)
        [
          d.format(r.day),
          r.userCode,
          r.userName,
          r.department,
          r.firstIn == null ? '' : t.format(r.firstIn!),
          r.lastOut == null ? '' : t.format(r.lastOut!),
          dur(r.worked),
          r.events,
        ],
    ]);
    if (ok) await AppDb.instance.audit(actor, 'Attendance exported', '${rows.length} rows');
    return ok;
  }

  Future<bool> exportUsersCsv({required String actor}) async {
    final users = await AppDb.instance.users();
    final d = DateFormat('yyyy-MM-dd');
    final ok = await _save('users-${DateFormat('yyyyMMdd').format(DateTime.now())}.csv', [
      [
        'Employee ID',
        'Name',
        'Department',
        'Role',
        'Status',
        'Phone',
        'Email',
        'Left palm',
        'Right palm',
        'Valid from',
        'Valid until',
      ],
      for (final u in users)
        [
          u.code,
          u.name,
          u.departmentName,
          roleLabel(u.role),
          u.status.name,
          u.phone,
          u.email,
          u.hasLeft ? 'Yes' : 'No',
          u.hasRight ? 'Yes' : 'No',
          u.validFrom == null ? '' : d.format(u.validFrom!),
          u.validUntil == null ? '' : d.format(u.validUntil!),
        ],
    ]);
    if (ok) await AppDb.instance.audit(actor, 'User list exported', '${users.length} users');
    return ok;
  }

  /// Wipes every user, template, log and setting (factory reset).
  Future<void> factoryReset() async {
    await PalmBridge.instance.deleteAllFeatures();
    await AppDb.instance.wipeAll();
    await AppSettings.instance.load();
    await DeviceBridge.instance.setLauncherMode(false);
    await DeviceBridge.instance.setBootStart(false);
  }
}
