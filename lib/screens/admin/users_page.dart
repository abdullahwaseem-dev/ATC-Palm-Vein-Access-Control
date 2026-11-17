// Copyright (c) 2026 ATC. All rights reserved.
// Proprietary and confidential. Use, copying, modification or distribution without
// written permission from ATC is prohibited. See LICENSE in the repository root.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/auth.dart';
import '../../core/backup.dart';
import '../../core/db.dart';
import '../../core/models.dart';
import '../../widgets/common.dart';
import 'user_edit_page.dart';

class UsersPage extends StatefulWidget {
  const UsersPage({super.key});
  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  final _search = TextEditingController();
  String _filter = 'all';
  int? _dept;
  List<AppUser> _users = [];
  List<Department> _depts = [];
  bool _loading = true;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final users = await AppDb.instance.users(query: _search.text, departmentId: _dept, filter: _filter);
    final depts = await AppDb.instance.departments();
    if (!mounted) return;
    setState(() {
      _users = users;
      _depts = depts;
      _loading = false;
    });
  }

  Future<void> _open([AppUser? u]) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => UserEditPage(user: u)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Add user'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      hintText: 'Search name, ID, phone or email',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _search.clear();
                                _load();
                              },
                            ),
                    ),
                    onChanged: (_) {
                      _debounce?.cancel();
                      _debounce = Timer(const Duration(milliseconds: 250), _load);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (v) async {
                    if (v == 'export') {
                      final ok = await BackupService.instance.exportUsersCsv(actor: AuthService.instance.actor);
                      if (context.mounted && ok) toast(context, 'User list exported');
                    }
                  },
                  itemBuilder: (_) => const [PopupMenuItem(value: 'export', child: Text('Export users (CSV)'))],
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
                for (final (k, label) in const [
                  ('all', 'All'),
                  ('enrolled', 'Enrolled'),
                  ('not_enrolled', 'No palm'),
                  ('admins', 'Admins'),
                  ('suspended', 'Suspended'),
                  ('expired', 'Expired'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: _filter == k,
                      onSelected: (_) {
                        setState(() => _filter = k);
                        _load();
                      },
                    ),
                  ),
                DropdownButton<int?>(
                  value: _dept,
                  hint: const Text('Department'),
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
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('${_users.length} user(s)', style: Theme.of(context).textTheme.labelMedium),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _users.isEmpty
                ? const Center(child: Text('No users found'))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                    itemCount: _users.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final u = _users[i];
                      final expired = u.validUntil != null && u.validUntil!.isBefore(DateTime.now());
                      return Card(
                        child: ListTile(
                          onTap: () => _open(u),
                          leading: UserAvatar(user: u),
                          title: Text(u.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            [u.code, if (u.departmentName != null) u.departmentName!, roleLabel(u.role)].join(' · '),
                          ),
                          trailing: Wrap(
                            spacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (u.status == UserStatus.suspended) const StatusPill('Suspended', Brand.denied),
                              if (expired) const StatusPill('Expired', Brand.warning),
                              StatusPill(
                                u.palmCount == 0 ? 'No palm' : '${u.palmCount} palm${u.palmCount > 1 ? 's' : ''}',
                                u.palmCount == 0 ? Colors.grey : Brand.granted,
                                icon: Icons.back_hand_outlined,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
