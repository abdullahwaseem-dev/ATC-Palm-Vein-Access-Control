// Copyright (c) 2026 ATC. All rights reserved.
// Proprietary and confidential. Use, copying, modification or distribution without
// written permission from ATC is prohibited. See LICENSE in the repository root.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/auth.dart';
import '../../core/backup.dart';
import '../../core/db.dart';
import '../../core/models.dart';
import '../../widgets/common.dart';

class AttendancePage extends StatefulWidget {
  const AttendancePage({super.key});
  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage> {
  late DateTimeRange _range;
  int? _dept;
  List<Department> _depts = [];
  List<AttendanceDay> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    _range = DateTimeRange(
      start: today.subtract(Duration(days: today.weekday - 1)),
      end: today,
    );
    _load();
  }

  Future<void> _load() async {
    final rows = await AppDb.instance.attendance(
      _range.start,
      _range.end.add(const Duration(days: 1)),
      departmentId: _dept,
    );
    final depts = await AppDb.instance.departments();
    if (mounted) {
      setState(() {
        _rows = rows;
        _depts = depts;
        _loading = false;
      });
    }
  }

  String _dur(Duration? d) => d == null ? '—' : '${d.inHours}h ${(d.inMinutes % 60).toString().padLeft(2, '0')}m';

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d MMM');
    final tf = DateFormat('HH:mm');
    final total = _rows.fold<Duration>(Duration.zero, (s, r) => s + (r.worked ?? Duration.zero));
    final people = _rows.map((r) => r.userId).toSet().length;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ActionChip(
                avatar: const Icon(Icons.date_range, size: 18),
                label: Text('${df.format(_range.start)} – ${df.format(_range.end)}'),
                onPressed: () async {
                  final r = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                    initialDateRange: _range,
                  );
                  if (r != null) {
                    setState(() => _range = r);
                    _load();
                  }
                },
              ),
              for (final (label, days) in const [('Today', 0), ('7 days', 6), ('30 days', 29)])
                ActionChip(
                  label: Text(label),
                  onPressed: () {
                    final now = DateTime.now();
                    final t = DateTime(now.year, now.month, now.day);
                    setState(
                      () => _range = DateTimeRange(
                        start: t.subtract(Duration(days: days)),
                        end: t,
                      ),
                    );
                    _load();
                  },
                ),
              DropdownButton<int?>(
                value: _dept,
                underline: const SizedBox.shrink(),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All departments')),
                  for (final d in _depts) DropdownMenuItem(value: d.id, child: Text(d.name)),
                ],
                onChanged: (v) {
                  setState(() => _dept = v);
                  _load();
                },
              ),
              FilledButton.tonalIcon(
                onPressed: () async {
                  final ok = await BackupService.instance.exportAttendanceCsv(_rows, actor: AuthService.instance.actor);
                  if (context.mounted && ok) toast(context, 'Attendance exported');
                },
                icon: const Icon(Icons.file_download_outlined),
                label: const Text('Export CSV'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              StatusPill('$people people', Brand.blue, icon: Icons.people_outline),
              const SizedBox(width: 6),
              StatusPill('${_rows.length} day records', Brand.charcoal),
              const SizedBox(width: 6),
              StatusPill('${total.inHours}h total', Brand.granted, icon: Icons.timer_outlined),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _rows.isEmpty
              ? const Center(child: Text('No attendance in this period'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: _rows.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, i) {
                    final r = _rows[i];
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Brand.blue.withValues(alpha: .1),
                          child: Text(
                            DateFormat('d').format(r.day),
                            style: const TextStyle(color: Brand.blue, fontWeight: FontWeight.w700),
                          ),
                        ),
                        title: Text(r.userName, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          '${DateFormat('EEE d MMM').format(r.day)} · ${r.userCode}'
                          '${r.department == null ? '' : ' · ${r.department}'}',
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${r.firstIn == null ? '—' : tf.format(r.firstIn!)} → ${r.lastOut == null ? '—' : tf.format(r.lastOut!)}',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            Text(_dur(r.worked), style: const TextStyle(color: Colors.black54, fontSize: 12)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
