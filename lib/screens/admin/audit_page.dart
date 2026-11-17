// Copyright (c) 2026 ATC. All rights reserved.
// Proprietary and confidential. Use, copying, modification or distribution without
// written permission from ATC is prohibited. See LICENSE in the repository root.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/db.dart';
import '../../core/models.dart';

/// History of administrative actions (who changed what, when). Admins cannot delete entries from the UI.
class AuditPage extends StatelessWidget {
  const AuditPage({super.key});

  IconData _icon(String a) {
    final x = a.toLowerCase();
    if (x.contains('login') || x.contains('logout')) return Icons.login;
    if (x.contains('failed') || x.contains('refused')) return Icons.gpp_bad_outlined;
    if (x.contains('palm')) return Icons.back_hand_outlined;
    if (x.contains('user')) return Icons.person_outline;
    if (x.contains('backup') || x.contains('export') || x.contains('restore')) return Icons.save_alt;
    if (x.contains('setting') || x.contains('pin')) return Icons.settings_outlined;
    return Icons.history;
  }

  @override
  Widget build(BuildContext context) {
    final f = DateFormat('d MMM yyyy · HH:mm:ss');
    return FutureBuilder<List<AuditEntry>>(
      future: AppDb.instance.auditLog(limit: 1000),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final items = snap.data!;
        if (items.isEmpty) return const Center(child: Text('No administrative activity yet'));
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 6),
          itemBuilder: (context, i) {
            final e = items[i];
            final bad = e.action.contains('Failed') || e.action.contains('refused');
            return Card(
              child: ListTile(
                leading: Icon(_icon(e.action), color: bad ? Colors.red : null),
                title: Text(e.action, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text([f.format(e.ts), e.actor, if (e.details.isNotEmpty) e.details].join(' · ')),
              ),
            );
          },
        );
      },
    );
  }
}
