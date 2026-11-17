// Copyright (c) 2026 ATC. All rights reserved.
// Proprietary and confidential. Use, copying, modification or distribution without
// written permission from ATC is prohibited. See LICENSE in the repository root.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/auth.dart';
import '../../core/backup.dart';
import '../../core/db.dart';
import '../../core/models.dart';
import '../../widgets/common.dart';

class LogsPage extends StatefulWidget {
  const LogsPage({super.key});
  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  final _search = TextEditingController();
  DateTimeRange? _range;
  bool? _granted;
  List<AccessLog> _logs = [];
  bool _loading = true;
  Timer? _debounce;
  static const _limit = 1000;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _range = DateTimeRange(
      start: DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6)),
      end: DateTime(now.year, now.month, now.day),
    );
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final logs = await AppDb.instance.logs(
      from: _range?.start,
      to: _range?.end.add(const Duration(days: 1)),
      granted: _granted,
      query: _search.text,
      limit: _limit,
    );
    if (mounted) {
      setState(() {
        _logs = logs;
        _loading = false;
      });
    }
  }

  Future<void> _pickRange() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _range,
    );
    if (r != null) {
      setState(() => _range = r);
      _load();
    }
  }

  Future<void> _export() async {
    final all = await AppDb.instance.logs(
      from: _range?.start,
      to: _range?.end.add(const Duration(days: 1)),
      granted: _granted,
      query: _search.text,
      limit: 1000000,
    );
    final ok = await BackupService.instance.exportLogsCsv(all, actor: AuthService.instance.actor);
    if (mounted && ok) toast(context, 'Exported ${all.length} records');
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d MMM');
    final tf = DateFormat('d MMM yyyy · HH:mm:ss');
    final granted = _logs.where((l) => l.granted).length;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  decoration: const InputDecoration(
                    hintText: 'Search name, ID or department',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (_) {
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 250), _load);
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Export CSV',
                onPressed: _export,
                icon: const Icon(Icons.file_download_outlined),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              ActionChip(
                avatar: const Icon(Icons.date_range, size: 18),
                label: Text(_range == null ? 'All dates' : '${df.format(_range!.start)} – ${df.format(_range!.end)}'),
                onPressed: _pickRange,
              ),
              const SizedBox(width: 8),
              for (final (v, label) in const [(null, 'All'), (true, 'Granted'), (false, 'Denied')])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(label),
                    selected: _granted == v,
                    onSelected: (_) {
                      setState(() => _granted = v);
                      _load();
                    },
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Text(
                '${_logs.length}${_logs.length == _limit ? '+' : ''} records',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const Spacer(),
              StatusPill('$granted granted', Brand.granted),
              const SizedBox(width: 6),
              StatusPill('${_logs.length - granted} denied', Brand.denied),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _logs.isEmpty
              ? const Center(child: Text('No records for this filter'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: _logs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, i) {
                    final l = _logs[i];
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: (l.granted ? Brand.granted : Brand.denied).withValues(alpha: .12),
                          child: Icon(
                            l.granted ? Icons.check : Icons.close,
                            color: l.granted ? Brand.granted : Brand.denied,
                          ),
                        ),
                        title: Text(
                          l.userName ?? 'Unknown person',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          [
                            tf.format(l.ts),
                            if (l.userCode != null) l.userCode!,
                            methodLabel(l.method),
                            if (!l.granted) Reason.label(l.reason),
                          ].join(' · '),
                        ),
                        trailing: l.direction.isEmpty
                            ? (l.score != null
                                  ? Text('${l.score}', style: const TextStyle(color: Colors.black45))
                                  : null)
                            : StatusPill(
                                l.direction == 'in' ? 'IN' : 'OUT',
                                l.direction == 'in' ? Brand.blue : Brand.warning,
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
