// Copyright (c) 2026 ATC. All rights reserved.
// Proprietary and confidential. Use, copying, modification or distribution without
// written permission from ATC is prohibited. See LICENSE in the repository root.

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models.dart';

/// SQLite store in app-private storage. Palm templates are stored only as
/// Android-Keystore-encrypted tokens (see SecureVault.kt).
class AppDb {
  AppDb._();
  static final instance = AppDb._();
  late Database db;

  Future<void> open() async {
    final path = p.join(await getDatabasesPath(), 'atc_palm_access.db');
    db = await openDatabase(
      path,
      version: 1,
      onConfigure: (d) async => d.execute('PRAGMA foreign_keys = ON'),
      onCreate: (d, v) async {
        final b = d.batch();
        b.execute('''CREATE TABLE departments(
          id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE)''');
        b.execute('''CREATE TABLE schedules(
          id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, days INTEGER NOT NULL,
          start_min INTEGER NOT NULL, end_min INTEGER NOT NULL)''');
        b.execute('''CREATE TABLE users(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          code TEXT NOT NULL UNIQUE, name TEXT NOT NULL,
          department_id INTEGER REFERENCES departments(id) ON DELETE SET NULL,
          role TEXT NOT NULL DEFAULT 'employee', phone TEXT, email TEXT, photo TEXT,
          qr_code TEXT UNIQUE, status TEXT NOT NULL DEFAULT 'active',
          valid_from INTEGER, valid_until INTEGER,
          schedule_id INTEGER REFERENCES schedules(id) ON DELETE SET NULL,
          notes TEXT,
          left_palm_id TEXT UNIQUE, left_feature TEXT,
          right_palm_id TEXT UNIQUE, right_feature TEXT,
          created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)''');
        b.execute('''CREATE TABLE access_logs(
          id INTEGER PRIMARY KEY AUTOINCREMENT, ts INTEGER NOT NULL,
          user_id INTEGER, user_name TEXT, user_code TEXT, department TEXT,
          method TEXT NOT NULL, granted INTEGER NOT NULL, reason TEXT NOT NULL,
          score INTEGER, direction TEXT NOT NULL DEFAULT '')''');
        b.execute('CREATE INDEX idx_logs_ts ON access_logs(ts)');
        b.execute('CREATE INDEX idx_logs_user ON access_logs(user_id, ts)');
        b.execute('''CREATE TABLE audit_logs(
          id INTEGER PRIMARY KEY AUTOINCREMENT, ts INTEGER NOT NULL,
          actor TEXT NOT NULL, action TEXT NOT NULL, details TEXT)''');
        b.execute('CREATE INDEX idx_audit_ts ON audit_logs(ts)');
        b.execute('CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT)');
        b.insert('schedules', AccessSchedule(name: 'Always (24/7)').toMap()..remove('id'));
        b.insert(
          'schedules',
          AccessSchedule(name: 'Office hours', days: 0x1F, startMinute: 7 * 60, endMinute: 19 * 60).toMap()
            ..remove('id'),
        );
        b.insert('departments', {'name': 'General'});
        await b.commit(noResult: true);
      },
    );
  }

  // ------------------------------------------------------------------ settings

  Future<Map<String, String>> allSettings() async {
    final rows = await db.query('settings');
    return {for (final r in rows) r['key'] as String: (r['value'] as String?) ?? ''};
  }

  Future<void> putSetting(String key, String value) =>
      db.insert('settings', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);

  // ------------------------------------------------------------------ users

  static const _userSelect = '''SELECT u.*, d.name AS department_name FROM users u
      LEFT JOIN departments d ON d.id = u.department_id''';

  Future<List<AppUser>> users({String query = '', int? departmentId, String filter = 'all'}) async {
    final where = <String>[];
    final args = <Object?>[];
    if (query.trim().isNotEmpty) {
      where.add('(u.name LIKE ? OR u.code LIKE ? OR u.phone LIKE ? OR u.email LIKE ?)');
      final q = '%${query.trim()}%';
      args.addAll([q, q, q, q]);
    }
    if (departmentId != null) {
      where.add('u.department_id = ?');
      args.add(departmentId);
    }
    switch (filter) {
      case 'enrolled':
        where.add('(u.left_palm_id IS NOT NULL OR u.right_palm_id IS NOT NULL)');
      case 'not_enrolled':
        where.add('u.left_palm_id IS NULL AND u.right_palm_id IS NULL');
      case 'suspended':
        where.add("u.status = 'suspended'");
      case 'admins':
        where.add("u.role = 'admin'");
      case 'expired':
        where.add('u.valid_until IS NOT NULL AND u.valid_until < ?');
        args.add(DateTime.now().millisecondsSinceEpoch);
    }
    final sql = '$_userSelect ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'} ORDER BY u.name COLLATE NOCASE';
    return (await db.rawQuery(sql, args)).map(AppUser.fromMap).toList();
  }

  Future<AppUser?> userById(int id) async {
    final r = await db.rawQuery('$_userSelect WHERE u.id = ?', [id]);
    return r.isEmpty ? null : AppUser.fromMap(r.first);
  }

  Future<AppUser?> userByPalmId(String palmId) async {
    final r = await db.rawQuery('$_userSelect WHERE u.left_palm_id = ? OR u.right_palm_id = ?', [palmId, palmId]);
    return r.isEmpty ? null : AppUser.fromMap(r.first);
  }

  Future<AppUser?> userByQr(String qr) async {
    final r = await db.rawQuery('$_userSelect WHERE u.qr_code = ?', [qr]);
    return r.isEmpty ? null : AppUser.fromMap(r.first);
  }

  Future<bool> codeTaken(String code, {int? exceptId}) async {
    final r = await db.query('users', columns: ['id'], where: 'code = ? AND id IS NOT ?', whereArgs: [code, exceptId]);
    return r.isNotEmpty;
  }

  Future<bool> qrTaken(String qr, {int? exceptId}) async {
    final r = await db.query('users', columns: ['id'], where: 'qr_code = ? AND id IS NOT ?', whereArgs: [qr, exceptId]);
    return r.isNotEmpty;
  }

  Future<int> saveUser(AppUser u) async {
    u.updatedAt = DateTime.now();
    final m = u.toMap()..remove('id');
    if (u.id == null) {
      u.id = await db.insert('users', m);
    } else {
      await db.update('users', m, where: 'id = ?', whereArgs: [u.id]);
    }
    return u.id!;
  }

  Future<void> deleteUser(int id) => db.delete('users', where: 'id = ?', whereArgs: [id]);

  Future<List<AppUser>> enrolledUsersWithTemplates() async => (await db.rawQuery(
    '$_userSelect WHERE u.left_feature IS NOT NULL OR u.right_feature IS NOT NULL',
  )).map(AppUser.fromMap).toList();

  Future<Map<String, int>> userStats() async {
    final r = (await db.rawQuery('''SELECT COUNT(*) AS total,
        SUM(CASE WHEN left_palm_id IS NOT NULL OR right_palm_id IS NOT NULL THEN 1 ELSE 0 END) AS enrolled,
        SUM(CASE WHEN left_palm_id IS NOT NULL THEN 1 ELSE 0 END) + SUM(CASE WHEN right_palm_id IS NOT NULL THEN 1 ELSE 0 END) AS palms,
        SUM(CASE WHEN status = 'suspended' THEN 1 ELSE 0 END) AS suspended,
        SUM(CASE WHEN role = 'admin' THEN 1 ELSE 0 END) AS admins
        FROM users''')).first;
    return r.map((k, v) => MapEntry(k, (v as int?) ?? 0));
  }

  // ------------------------------------------------------------------ departments & schedules

  Future<List<Department>> departments() async =>
      (await db.query('departments', orderBy: 'name COLLATE NOCASE')).map(Department.fromMap).toList();

  Future<int> saveDepartment(Department d) async {
    if (d.id == null) return d.id = await db.insert('departments', {'name': d.name});
    await db.update('departments', {'name': d.name}, where: 'id = ?', whereArgs: [d.id]);
    return d.id!;
  }

  Future<void> deleteDepartment(int id) => db.delete('departments', where: 'id = ?', whereArgs: [id]);

  Future<Map<int, int>> departmentCounts() async {
    final r = await db.rawQuery('SELECT department_id, COUNT(*) c FROM users GROUP BY department_id');
    return {
      for (final x in r)
        if (x['department_id'] != null) x['department_id'] as int: x['c'] as int,
    };
  }

  Future<List<AccessSchedule>> schedules() async =>
      (await db.query('schedules', orderBy: 'id')).map(AccessSchedule.fromMap).toList();

  Future<AccessSchedule?> scheduleById(int id) async {
    final r = await db.query('schedules', where: 'id = ?', whereArgs: [id]);
    return r.isEmpty ? null : AccessSchedule.fromMap(r.first);
  }

  Future<int> saveSchedule(AccessSchedule s) async {
    final m = s.toMap()..remove('id');
    if (s.id == null) return s.id = await db.insert('schedules', m);
    await db.update('schedules', m, where: 'id = ?', whereArgs: [s.id]);
    return s.id!;
  }

  Future<void> deleteSchedule(int id) => db.delete('schedules', where: 'id = ?', whereArgs: [id]);

  // ------------------------------------------------------------------ access logs

  Future<int> insertLog(AccessLog l) => db.insert('access_logs', l.toMap()..remove('id'));

  Future<List<AccessLog>> logs({
    DateTime? from,
    DateTime? to,
    bool? granted,
    int? userId,
    String query = '',
    int limit = 500,
    int offset = 0,
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    if (from != null) {
      where.add('ts >= ?');
      args.add(from.millisecondsSinceEpoch);
    }
    if (to != null) {
      where.add('ts < ?');
      args.add(to.millisecondsSinceEpoch);
    }
    if (granted != null) {
      where.add('granted = ?');
      args.add(granted ? 1 : 0);
    }
    if (userId != null) {
      where.add('user_id = ?');
      args.add(userId);
    }
    if (query.trim().isNotEmpty) {
      where.add('(user_name LIKE ? OR user_code LIKE ? OR department LIKE ?)');
      final q = '%${query.trim()}%';
      args.addAll([q, q, q]);
    }
    final rows = await db.query(
      'access_logs',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args,
      orderBy: 'ts DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(AccessLog.fromMap).toList();
  }

  Future<AccessLog?> lastLogForUser(int userId, {DateTime? since, bool onlyGranted = true}) async {
    final r = await db.query(
      'access_logs',
      where: 'user_id = ? ${onlyGranted ? 'AND granted = 1' : ''} ${since != null ? 'AND ts >= ?' : ''}',
      whereArgs: [userId, if (since != null) since.millisecondsSinceEpoch],
      orderBy: 'ts DESC',
      limit: 1,
    );
    return r.isEmpty ? null : AccessLog.fromMap(r.first);
  }

  Future<(int, int)> countsBetween(DateTime from, DateTime to) async {
    final r = (await db.rawQuery(
      'SELECT SUM(granted) g, SUM(1 - granted) d FROM access_logs WHERE ts >= ? AND ts < ?',
      [from.millisecondsSinceEpoch, to.millisecondsSinceEpoch],
    )).first;
    return ((r['g'] as int?) ?? 0, (r['d'] as int?) ?? 0);
  }

  /// Granted/denied counts per day for the last [days] days (oldest first).
  Future<List<(DateTime, int, int)>> dailyCounts(int days) async {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day).subtract(Duration(days: days - 1));
    final out = <(DateTime, int, int)>[];
    for (var i = 0; i < days; i++) {
      final d = start.add(Duration(days: i));
      final (g, x) = await countsBetween(d, d.add(const Duration(days: 1)));
      out.add((d, g, x));
    }
    return out;
  }

  /// Granted entries per hour today.
  Future<List<int>> hourlyToday() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final rows = await db.query(
      'access_logs',
      columns: ['ts'],
      where: 'ts >= ? AND granted = 1',
      whereArgs: [start.millisecondsSinceEpoch],
    );
    final buckets = List<int>.filled(24, 0);
    for (final r in rows) {
      buckets[DateTime.fromMillisecondsSinceEpoch(r['ts'] as int).hour]++;
    }
    return buckets;
  }

  /// Users whose latest granted event today was a check-in.
  Future<int> presentNow() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    final r = await db.rawQuery(
      '''SELECT COUNT(*) c FROM (
        SELECT user_id, direction FROM access_logs a
        WHERE granted = 1 AND ts >= ? AND user_id IS NOT NULL AND direction != ''
          AND ts = (SELECT MAX(ts) FROM access_logs b WHERE b.user_id = a.user_id AND b.granted = 1 AND b.ts >= ? AND b.direction != ''))
        WHERE direction = 'in' ''',
      [start, start],
    );
    return (r.first['c'] as int?) ?? 0;
  }

  Future<List<AttendanceDay>> attendance(DateTime from, DateTime to, {int? departmentId}) async {
    final rows = await db.rawQuery(
      '''SELECT l.user_id, l.user_name, l.user_code, l.department, l.ts, l.direction
        FROM access_logs l ${departmentId != null ? 'JOIN users u ON u.id = l.user_id' : ''}
        WHERE l.granted = 1 AND l.user_id IS NOT NULL AND l.ts >= ? AND l.ts < ?
        ${departmentId != null ? 'AND u.department_id = ?' : ''}
        ORDER BY l.ts''',
      [from.millisecondsSinceEpoch, to.millisecondsSinceEpoch, ?departmentId],
    );
    final map = <String, Map<String, Object?>>{};
    for (final r in rows) {
      final ts = DateTime.fromMillisecondsSinceEpoch(r['ts'] as int);
      final day = DateTime(ts.year, ts.month, ts.day);
      final key = '${r['user_id']}_${day.millisecondsSinceEpoch}';
      final e = map.putIfAbsent(
        key,
        () => {'row': r, 'day': day, 'in': null, 'out': null, 'n': 0, 'first': ts, 'last': ts},
      );
      e['n'] = (e['n'] as int) + 1;
      e['last'] = ts;
      final dir = r['direction'] as String;
      if (dir == 'in' && e['in'] == null) e['in'] = ts;
      if (dir == 'out') e['out'] = ts;
    }
    return map.values.map((e) {
        final r = e['row'] as Map<String, Object?>;
        // Access-only terminals have no direction: use first/last event of the day.
        final firstIn = (e['in'] as DateTime?) ?? e['first'] as DateTime;
        final lastOut = (e['out'] as DateTime?) ?? ((e['n'] as int) > 1 ? e['last'] as DateTime : null);
        return AttendanceDay(
          userId: r['user_id'] as int,
          userName: (r['user_name'] as String?) ?? '',
          userCode: (r['user_code'] as String?) ?? '',
          department: r['department'] as String?,
          day: e['day'] as DateTime,
          firstIn: firstIn,
          lastOut: lastOut,
          events: e['n'] as int,
        );
      }).toList()
      ..sort((a, b) => b.day.compareTo(a.day) != 0 ? b.day.compareTo(a.day) : a.userName.compareTo(b.userName));
  }

  Future<int> purgeLogsOlderThan(int days) => db.delete(
    'access_logs',
    where: 'ts < ?',
    whereArgs: [DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch],
  );

  Future<int> clearLogs() => db.delete('access_logs');

  // ------------------------------------------------------------------ audit

  Future<void> audit(String actor, String action, [String details = '']) => db.insert('audit_logs', {
    'ts': DateTime.now().millisecondsSinceEpoch,
    'actor': actor,
    'action': action,
    'details': details,
  });

  Future<List<AuditEntry>> auditLog({int limit = 500}) async =>
      (await db.query('audit_logs', orderBy: 'ts DESC', limit: limit)).map(AuditEntry.fromMap).toList();

  Future<int> purgeAuditOlderThan(int days) => db.delete(
    'audit_logs',
    where: 'ts < ?',
    whereArgs: [DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch],
  );

  // ------------------------------------------------------------------ wipe

  Future<void> wipeAll() async {
    await db.transaction((t) async {
      for (final table in ['access_logs', 'audit_logs', 'users', 'departments', 'schedules', 'settings']) {
        await t.delete(table);
      }
    });
  }
}
