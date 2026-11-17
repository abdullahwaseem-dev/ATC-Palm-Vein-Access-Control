// Copyright (c) 2026 ATC. All rights reserved.
// Proprietary and confidential. Use, copying, modification or distribution without
// written permission from ATC is prohibited. See LICENSE in the repository root.

import 'package:flutter/material.dart';

import '../../core/auth.dart';
import '../../widgets/common.dart';
import 'attendance_page.dart';
import 'audit_page.dart';
import 'dashboard_page.dart';
import 'device_page.dart';
import 'logs_page.dart';
import 'org_page.dart';
import 'settings_page.dart';
import 'users_page.dart';

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});
  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _index = 0;

  static const _items = [
    (Icons.dashboard_outlined, Icons.dashboard, 'Dashboard'),
    (Icons.people_outline, Icons.people, 'Users'),
    (Icons.receipt_long_outlined, Icons.receipt_long, 'Access log'),
    (Icons.schedule_outlined, Icons.schedule, 'Attendance'),
    (Icons.apartment_outlined, Icons.apartment, 'Departments & schedules'),
    (Icons.sensors_outlined, Icons.sensors, 'Scanner & device'),
    (Icons.settings_outlined, Icons.settings, 'Settings'),
    (Icons.policy_outlined, Icons.policy, 'Audit trail'),
  ];

  Widget _page() => switch (_index) {
    0 => DashboardPage(onNavigate: (i) => setState(() => _index = i)),
    1 => const UsersPage(),
    2 => const LogsPage(),
    3 => const AttendancePage(),
    4 => const OrgPage(),
    5 => const DevicePage(),
    6 => const SettingsPage(),
    _ => const AuditPage(),
  };

  Future<void> _lock() async {
    await AuthService.instance.logout();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 840;
    final title = _items[_index].$3;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _lock();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Center(
                child: Text(
                  AuthService.instance.actor,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.black54),
                ),
              ),
            ),
            IconButton(tooltip: 'Lock & return to terminal', onPressed: _lock, icon: const Icon(Icons.lock_outline)),
          ],
        ),
        drawer: wide
            ? null
            : NavigationDrawer(
                selectedIndex: _index,
                onDestinationSelected: (i) {
                  Navigator.pop(context);
                  setState(() => _index = i);
                },
                children: [
                  const Padding(padding: EdgeInsets.fromLTRB(28, 20, 16, 16), child: BrandLogo(height: 32)),
                  for (final it in _items)
                    NavigationDrawerDestination(icon: Icon(it.$1), selectedIcon: Icon(it.$2), label: Text(it.$3)),
                  const Divider(indent: 28, endIndent: 28),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: ListTile(leading: const Icon(Icons.lock_outline), title: const Text('Lock'), onTap: _lock),
                  ),
                ],
              ),
        body: Row(
          children: [
            if (wide)
              NavigationRail(
                extended: MediaQuery.sizeOf(context).width >= 1100,
                selectedIndex: _index,
                onDestinationSelected: (i) => setState(() => _index = i),
                leading: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: BrandMark(size: 36)),
                destinations: [
                  for (final it in _items)
                    NavigationRailDestination(icon: Icon(it.$1), selectedIcon: Icon(it.$2), label: Text(it.$3)),
                ],
              ),
            Expanded(child: _page()),
          ],
        ),
      ),
    );
  }
}
