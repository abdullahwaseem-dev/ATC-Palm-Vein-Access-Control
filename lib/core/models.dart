// Copyright (c) 2026 ATC. All rights reserved.
// Proprietary and confidential. Use, copying, modification or distribution without
// written permission from ATC is prohibited. See LICENSE in the repository root.

/// Plain data classes persisted in SQLite.
library;

enum UserRole { admin, employee, visitor, contractor }

enum UserStatus { active, suspended }

String roleLabel(UserRole r) => switch (r) {
  UserRole.admin => 'Administrator',
  UserRole.employee => 'Employee',
  UserRole.visitor => 'Visitor',
  UserRole.contractor => 'Contractor',
};

class AppUser {
  int? id;
  String code;
  String name;
  int? departmentId;
  UserRole role;
  String? phone;
  String? email;
  String? photoPath;
  String? qrCode;
  UserStatus status;
  DateTime? validFrom;
  DateTime? validUntil;
  int? scheduleId;
  String? notes;
  String? leftPalmId;
  String? leftFeature; // Keystore-encrypted token, never plaintext at rest
  String? rightPalmId;
  String? rightFeature;
  DateTime createdAt;
  DateTime updatedAt;

  // Joined, not stored.
  String? departmentName;

  AppUser({
    this.id,
    required this.code,
    required this.name,
    this.departmentId,
    this.role = UserRole.employee,
    this.phone,
    this.email,
    this.photoPath,
    this.qrCode,
    this.status = UserStatus.active,
    this.validFrom,
    this.validUntil,
    this.scheduleId,
    this.notes,
    this.leftPalmId,
    this.leftFeature,
    this.rightPalmId,
    this.rightFeature,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.departmentName,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  bool get hasLeft => (leftPalmId ?? '').isNotEmpty;
  bool get hasRight => (rightPalmId ?? '').isNotEmpty;
  int get palmCount => (hasLeft ? 1 : 0) + (hasRight ? 1 : 0);

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'code': code,
    'name': name,
    'department_id': departmentId,
    'role': role.name,
    'phone': phone,
    'email': email,
    'photo': photoPath,
    'qr_code': (qrCode ?? '').isEmpty ? null : qrCode,
    'status': status.name,
    'valid_from': validFrom?.millisecondsSinceEpoch,
    'valid_until': validUntil?.millisecondsSinceEpoch,
    'schedule_id': scheduleId,
    'notes': notes,
    'left_palm_id': (leftPalmId ?? '').isEmpty ? null : leftPalmId,
    'left_feature': leftFeature,
    'right_palm_id': (rightPalmId ?? '').isEmpty ? null : rightPalmId,
    'right_feature': rightFeature,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
  };

  static DateTime? _dt(Object? v) => v == null ? null : DateTime.fromMillisecondsSinceEpoch(v as int);

  factory AppUser.fromMap(Map<String, Object?> m) => AppUser(
    id: m['id'] as int?,
    code: m['code'] as String,
    name: m['name'] as String,
    departmentId: m['department_id'] as int?,
    role: UserRole.values.firstWhere((r) => r.name == m['role'], orElse: () => UserRole.employee),
    phone: m['phone'] as String?,
    email: m['email'] as String?,
    photoPath: m['photo'] as String?,
    qrCode: m['qr_code'] as String?,
    status: UserStatus.values.firstWhere((s) => s.name == m['status'], orElse: () => UserStatus.active),
    validFrom: _dt(m['valid_from']),
    validUntil: _dt(m['valid_until']),
    scheduleId: m['schedule_id'] as int?,
    notes: m['notes'] as String?,
    leftPalmId: m['left_palm_id'] as String?,
    leftFeature: m['left_feature'] as String?,
    rightPalmId: m['right_palm_id'] as String?,
    rightFeature: m['right_feature'] as String?,
    createdAt: _dt(m['created_at']),
    updatedAt: _dt(m['updated_at']),
    departmentName: m['department_name'] as String?,
  );
}

class Department {
  int? id;
  String name;
  Department({this.id, required this.name});
  Map<String, Object?> toMap() => {'id': id, 'name': name};
  factory Department.fromMap(Map<String, Object?> m) => Department(id: m['id'] as int?, name: m['name'] as String);
}

/// Weekly time window. [days] is a bitmask: Monday = bit 0 ... Sunday = bit 6.
class AccessSchedule {
  int? id;
  String name;
  int days;
  int startMinute;
  int endMinute;

  AccessSchedule({this.id, required this.name, this.days = 0x7F, this.startMinute = 0, this.endMinute = 1440});

  bool allows(DateTime t) {
    final dayBit = 1 << (t.weekday - 1);
    if (days & dayBit == 0) return false;
    final m = t.hour * 60 + t.minute;
    if (startMinute <= endMinute) return m >= startMinute && m < endMinute;
    return m >= startMinute || m < endMinute; // overnight shift, e.g. 22:00-06:00
  }

  static String fmt(int minute) {
    if (minute >= 1440) return '24:00';
    return '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
  }

  String get daysLabel {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    if (days == 0x7F) return 'Every day';
    if (days == 0x1F) return 'Mon–Fri';
    return [
      for (var i = 0; i < 7; i++)
        if (days & (1 << i) != 0) names[i],
    ].join(', ');
  }

  String get summary => '$daysLabel · ${fmt(startMinute)}–${fmt(endMinute)}';

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'days': days,
    'start_min': startMinute,
    'end_min': endMinute,
  };
  factory AccessSchedule.fromMap(Map<String, Object?> m) => AccessSchedule(
    id: m['id'] as int?,
    name: m['name'] as String,
    days: m['days'] as int,
    startMinute: m['start_min'] as int,
    endMinute: m['end_min'] as int,
  );
}

enum AccessMethod { palmLeft, palmRight, palm, qr }

String methodLabel(String m) => switch (m) {
  'palmLeft' => 'Left palm',
  'palmRight' => 'Right palm',
  'palm' => 'Palm',
  'qr' => 'QR code',
  _ => m,
};

/// Why an access attempt was granted or denied.
class Reason {
  static const granted = 'granted';
  static const unknown = 'unknown_palm';
  static const unknownQr = 'unknown_qr';
  static const suspended = 'suspended';
  static const notYetValid = 'not_yet_valid';
  static const expired = 'expired';
  static const outsideSchedule = 'outside_schedule';

  static String label(String r) => switch (r) {
    granted => 'Access granted',
    unknown => 'Palm not recognised',
    unknownQr => 'QR code not registered',
    suspended => 'Account suspended',
    notYetValid => 'Access not yet valid',
    expired => 'Access expired',
    outsideSchedule => 'Outside permitted hours',
    _ => r,
  };
}

class AccessLog {
  int? id;
  DateTime ts;
  int? userId;
  String? userName;
  String? userCode;
  String? department;
  String method;
  bool granted;
  String reason;
  int? score;
  String direction; // 'in', 'out' or '' (access-only terminal)

  AccessLog({
    this.id,
    required this.ts,
    this.userId,
    this.userName,
    this.userCode,
    this.department,
    required this.method,
    required this.granted,
    required this.reason,
    this.score,
    this.direction = '',
  });

  Map<String, Object?> toMap() => {
    'id': id,
    'ts': ts.millisecondsSinceEpoch,
    'user_id': userId,
    'user_name': userName,
    'user_code': userCode,
    'department': department,
    'method': method,
    'granted': granted ? 1 : 0,
    'reason': reason,
    'score': score,
    'direction': direction,
  };

  factory AccessLog.fromMap(Map<String, Object?> m) => AccessLog(
    id: m['id'] as int?,
    ts: DateTime.fromMillisecondsSinceEpoch(m['ts'] as int),
    userId: m['user_id'] as int?,
    userName: m['user_name'] as String?,
    userCode: m['user_code'] as String?,
    department: m['department'] as String?,
    method: m['method'] as String,
    granted: (m['granted'] as int) == 1,
    reason: m['reason'] as String,
    score: m['score'] as int?,
    direction: (m['direction'] as String?) ?? '',
  );
}

class AuditEntry {
  final int? id;
  final DateTime ts;
  final String actor;
  final String action;
  final String details;
  AuditEntry({this.id, required this.ts, required this.actor, required this.action, required this.details});
  factory AuditEntry.fromMap(Map<String, Object?> m) => AuditEntry(
    id: m['id'] as int?,
    ts: DateTime.fromMillisecondsSinceEpoch(m['ts'] as int),
    actor: m['actor'] as String,
    action: m['action'] as String,
    details: (m['details'] as String?) ?? '',
  );
}

/// One row of the attendance report: a user's first-in / last-out on a day.
class AttendanceDay {
  final int userId;
  final String userName;
  final String userCode;
  final String? department;
  final DateTime day;
  final DateTime? firstIn;
  final DateTime? lastOut;
  final int events;

  AttendanceDay({
    required this.userId,
    required this.userName,
    required this.userCode,
    this.department,
    required this.day,
    this.firstIn,
    this.lastOut,
    required this.events,
  });

  Duration? get worked =>
      (firstIn != null && lastOut != null && lastOut!.isAfter(firstIn!)) ? lastOut!.difference(firstIn!) : null;
}
