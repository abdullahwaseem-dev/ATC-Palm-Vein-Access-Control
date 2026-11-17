// Copyright (c) 2026 ATC. All rights reserved.
// Proprietary and confidential. Use, copying, modification or distribution without
// written permission from ATC is prohibited. See LICENSE in the repository root.

import 'package:flutter/material.dart';

import '../../core/auth.dart';
import '../../core/db.dart';
import '../../core/models.dart';
import '../../widgets/common.dart';

class OrgPage extends StatefulWidget {
  const OrgPage({super.key});
  @override
  State<OrgPage> createState() => _OrgPageState();
}

class _OrgPageState extends State<OrgPage> {
  List<Department> _depts = [];
  Map<int, int> _counts = {};
  List<AccessSchedule> _schedules = [];
  String get _actor => AuthService.instance.actor;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = await AppDb.instance.departments();
    final c = await AppDb.instance.departmentCounts();
    final s = await AppDb.instance.schedules();
    if (mounted) {
      setState(() {
        _depts = d;
        _counts = c;
        _schedules = s;
      });
    }
  }

  Future<void> _editDept([Department? d]) async {
    final ctl = TextEditingController(text: d?.name ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(d == null ? 'New department' : 'Rename department'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, ctl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      await AppDb.instance.saveDepartment(Department(id: d?.id, name: name));
      await AppDb.instance.audit(_actor, d == null ? 'Department created' : 'Department renamed', name);
    } catch (_) {
      if (mounted) toast(context, 'A department with that name already exists', error: true);
    }
    _load();
  }

  Future<void> _deleteDept(Department d) async {
    if (!await confirm(
      context,
      'Delete "${d.name}"?',
      'Users in this department will have no department.',
      ok: 'Delete',
      destructive: true,
    )) {
      return;
    }
    await AppDb.instance.deleteDepartment(d.id!);
    await AppDb.instance.audit(_actor, 'Department deleted', d.name);
    _load();
  }

  Future<void> _editSchedule([AccessSchedule? s]) async {
    final r = await showDialog<AccessSchedule>(
      context: context,
      builder: (_) => _ScheduleDialog(schedule: s),
    );
    if (r == null) return;
    await AppDb.instance.saveSchedule(r);
    await AppDb.instance.audit(_actor, s == null ? 'Schedule created' : 'Schedule updated', '${r.name}: ${r.summary}');
    _load();
  }

  Future<void> _deleteSchedule(AccessSchedule s) async {
    if (!await confirm(
      context,
      'Delete "${s.name}"?',
      'Users on this schedule will have no time restriction.',
      ok: 'Delete',
      destructive: true,
    )) {
      return;
    }
    await AppDb.instance.deleteSchedule(s.id!);
    await AppDb.instance.audit(_actor, 'Schedule deleted', s.name);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        Row(
          children: [
            const Expanded(child: SectionHeader('Departments')),
            Padding(
              padding: const EdgeInsets.only(right: 12, top: 12),
              child: TextButton.icon(
                onPressed: () => _editDept(),
                icon: const Icon(Icons.add),
                label: const Text('Add'),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card(
            child: Column(
              children: [
                if (_depts.isEmpty) const ListTile(title: Text('No departments')),
                for (final d in _depts)
                  ListTile(
                    leading: const Icon(Icons.apartment_outlined),
                    title: Text(d.name),
                    subtitle: Text('${_counts[d.id] ?? 0} user(s)'),
                    trailing: Wrap(
                      children: [
                        IconButton(onPressed: () => _editDept(d), icon: const Icon(Icons.edit_outlined)),
                        IconButton(onPressed: () => _deleteDept(d), icon: const Icon(Icons.delete_outline)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        Row(
          children: [
            const Expanded(child: SectionHeader('Access schedules')),
            Padding(
              padding: const EdgeInsets.only(right: 12, top: 12),
              child: TextButton.icon(
                onPressed: () => _editSchedule(),
                icon: const Icon(Icons.add),
                label: const Text('Add'),
              ),
            ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            'Assign a schedule to a user to limit when their palm opens the door. Overnight windows (e.g. 22:00–06:00) are supported.',
            style: TextStyle(color: Colors.black54),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card(
            child: Column(
              children: [
                for (final s in _schedules)
                  ListTile(
                    leading: const Icon(Icons.event_available_outlined),
                    title: Text(s.name),
                    subtitle: Text(s.summary),
                    trailing: Wrap(
                      children: [
                        IconButton(onPressed: () => _editSchedule(s), icon: const Icon(Icons.edit_outlined)),
                        IconButton(onPressed: () => _deleteSchedule(s), icon: const Icon(Icons.delete_outline)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ScheduleDialog extends StatefulWidget {
  final AccessSchedule? schedule;
  const _ScheduleDialog({this.schedule});
  @override
  State<_ScheduleDialog> createState() => _ScheduleDialogState();
}

class _ScheduleDialogState extends State<_ScheduleDialog> {
  late final _name = TextEditingController(text: widget.schedule?.name ?? '');
  late int _days = widget.schedule?.days ?? 0x1F;
  late int _start = widget.schedule?.startMinute ?? 8 * 60;
  late int _end = widget.schedule?.endMinute ?? 17 * 60;

  Future<void> _time(bool start) async {
    final m = start ? _start : _end;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: (m ~/ 60) % 24, minute: m % 60),
    );
    if (t != null) setState(() => start ? _start = t.hour * 60 + t.minute : _end = t.hour * 60 + t.minute);
  }

  @override
  Widget build(BuildContext context) {
    const names = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return AlertDialog(
      title: Text(widget.schedule == null ? 'New schedule' : 'Edit schedule'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 4,
              children: [
                for (var i = 0; i < 7; i++)
                  FilterChip(
                    label: Text(names[i]),
                    selected: _days & (1 << i) != 0,
                    onSelected: (v) => setState(() => _days = v ? _days | (1 << i) : _days & ~(1 << i)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _time(true),
                    child: Text('From ${AccessSchedule.fmt(_start)}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(onPressed: () => _time(false), child: Text('To ${AccessSchedule.fmt(_end)}')),
                ),
              ],
            ),
            TextButton(
              onPressed: () => setState(() {
                _start = 0;
                _end = 1440;
              }),
              child: const Text('All day'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _days == 0
              ? null
              : () {
                  final name = _name.text.trim().isEmpty ? 'Schedule' : _name.text.trim();
                  Navigator.pop(
                    context,
                    AccessSchedule(
                      id: widget.schedule?.id,
                      name: name,
                      days: _days,
                      startMinute: _start,
                      endMinute: _end,
                    ),
                  );
                },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
