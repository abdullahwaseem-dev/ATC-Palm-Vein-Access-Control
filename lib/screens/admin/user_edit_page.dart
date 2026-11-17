// Copyright (c) 2026 ATC. All rights reserved.
// Proprietary and confidential. Use, copying, modification or distribution without
// written permission from ATC is prohibited. See LICENSE in the repository root.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/app_state.dart';
import '../../core/auth.dart';
import '../../core/bridges.dart';
import '../../core/db.dart';
import '../../core/models.dart';
import '../../core/services.dart';
import '../../widgets/common.dart';
import '../enroll_screen.dart';

class UserEditPage extends StatefulWidget {
  final AppUser? user;
  const UserEditPage({super.key, this.user});
  @override
  State<UserEditPage> createState() => _UserEditPageState();
}

class _UserEditPageState extends State<UserEditPage> {
  final _form = GlobalKey<FormState>();
  late AppUser _u;
  late final _code = TextEditingController(text: _u.code);
  late final _name = TextEditingController(text: _u.name);
  late final _phone = TextEditingController(text: _u.phone ?? '');
  late final _email = TextEditingController(text: _u.email ?? '');
  late final _qr = TextEditingController(text: _u.qrCode ?? '');
  late final _notes = TextEditingController(text: _u.notes ?? '');
  List<Department> _depts = [];
  List<AccessSchedule> _schedules = [];
  bool _saving = false;
  bool _loaded = false;
  String get _actor => AuthService.instance.actor;

  @override
  void initState() {
    super.initState();
    _u = widget.user ?? AppUser(code: DateTime.now().millisecondsSinceEpoch.toString().substring(5), name: '');
    _loadRefs();
  }

  Future<void> _loadRefs() async {
    final d = await AppDb.instance.departments();
    final s = await AppDb.instance.schedules();
    if (!mounted) return;
    setState(() {
      _depts = d;
      _schedules = s;
      // Drop references to rows that no longer exist so dropdowns stay consistent.
      if (!d.any((x) => x.id == _u.departmentId)) _u.departmentId = null;
      if (!s.any((x) => x.id == _u.scheduleId)) _u.scheduleId = null;
      if (_u.id == null && _u.departmentId == null && d.isNotEmpty) _u.departmentId = d.first.id;
      if (_u.id == null && _u.scheduleId == null && s.isNotEmpty) _u.scheduleId = s.first.id;
      _loaded = true;
    });
  }

  Future<bool> _save({bool pop = true}) async {
    if (!_form.currentState!.validate()) return false;
    setState(() => _saving = true);
    final db = AppDb.instance;
    final code = _code.text.trim();
    final qr = _qr.text.trim();
    if (await db.codeTaken(code, exceptId: _u.id)) {
      setState(() => _saving = false);
      if (mounted) toast(context, 'Employee ID "$code" is already used', error: true);
      return false;
    }
    if (qr.isNotEmpty && await db.qrTaken(qr, exceptId: _u.id)) {
      setState(() => _saving = false);
      if (mounted) toast(context, 'That QR code is assigned to another user', error: true);
      return false;
    }
    final isNew = _u.id == null;
    _u
      ..code = code
      ..name = _name.text.trim()
      ..phone = _phone.text.trim().isEmpty ? null : _phone.text.trim()
      ..email = _email.text.trim().isEmpty ? null : _email.text.trim()
      ..qrCode = qr.isEmpty ? null : qr
      ..notes = _notes.text.trim().isEmpty ? null : _notes.text.trim();
    await db.saveUser(_u);
    _u = (await db.userById(_u.id!))!;
    await db.audit(_actor, isNew ? 'User created' : 'User updated', '${_u.code} ${_u.name}');
    setState(() => _saving = false);
    if (pop && mounted) Navigator.pop(context);
    return true;
  }

  Future<void> _pickPhoto(ImageSource src) async {
    try {
      final x = await ImagePicker().pickImage(source: src, maxWidth: 600, maxHeight: 600, imageQuality: 80);
      if (x == null) return;
      final dir = Directory(p.join((await getApplicationSupportDirectory()).path, 'photos'));
      await dir.create(recursive: true);
      final dest = p.join(dir.path, '${DateTime.now().microsecondsSinceEpoch}.jpg');
      await File(x.path).copy(dest);
      final old = _u.photoPath;
      setState(() => _u.photoPath = dest);
      if (old != null) File(old).delete().ignore();
    } catch (e) {
      if (mounted) toast(context, 'Could not load photo', error: true);
    }
  }

  Future<void> _enroll(String hand) async {
    if (!AppState.instance.ready) {
      toast(context, 'The palm scanner is not ready', error: true);
      return;
    }
    if (!await _save(pop: false)) return; // the user must exist before a template is attached
    if (!mounted) return;
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EnrollScreen(user: _u, hand: hand),
      ),
    );
    if (ok == true) {
      _u = (await AppDb.instance.userById(_u.id!))!;
      setState(() {});
      if (mounted) toast(context, '${hand == 'left' ? 'Left' : 'Right'} palm enrolled');
    }
  }

  Future<void> _removePalm(String hand) async {
    if (!await confirm(
      context,
      'Remove palm?',
      'The ${hand == 'left' ? 'left' : 'right'} palm template will be deleted.',
      ok: 'Remove',
      destructive: true,
    )) {
      return;
    }
    await PalmLibrary.instance.removeTemplate(_u, hand, actor: _actor);
    setState(() {});
  }

  Future<void> _delete() async {
    if (!await confirm(
      context,
      'Delete user?',
      '${_u.name} and their palm templates will be permanently deleted. Access history is kept.',
      ok: 'Delete',
      destructive: true,
    )) {
      return;
    }
    await PalmLibrary.instance.deleteUser(_u, actor: _actor);
    if (_u.photoPath != null) File(_u.photoPath!).delete().ignore();
    if (mounted) Navigator.pop(context);
  }

  Future<DateTime?> _pickDate(DateTime? initial) => showDatePicker(
    context: context,
    initialDate: initial ?? DateTime.now(),
    firstDate: DateTime(2020),
    lastDate: DateTime(2100),
  );

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d MMM yyyy');
    return Scaffold(
      appBar: AppBar(
        title: Text(_u.id == null ? 'New user' : 'Edit user'),
        actions: [
          if (_u.id != null)
            IconButton(tooltip: 'Delete user', onPressed: _delete, icon: const Icon(Icons.delete_outline)),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(onPressed: _saving ? null : () => _save(), child: const Text('Save')),
          ),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 40),
                children: [
                  const SizedBox(height: 16),
                  Center(
                    child: Stack(
                      children: [
                        UserAvatar(user: _u..name = _name.text, radius: 52),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: PopupMenuButton<String>(
                            icon: const CircleAvatar(
                              radius: 18,
                              backgroundColor: Brand.blue,
                              child: Icon(Icons.photo_camera, color: Colors.white, size: 18),
                            ),
                            onSelected: (v) {
                              if (v == 'camera') _pickPhoto(ImageSource.camera);
                              if (v == 'gallery') _pickPhoto(ImageSource.gallery);
                              if (v == 'remove') setState(() => _u.photoPath = null);
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(value: 'camera', child: Text('Take photo')),
                              const PopupMenuItem(value: 'gallery', child: Text('Choose from gallery')),
                              if (_u.photoPath != null)
                                const PopupMenuItem(value: 'remove', child: Text('Remove photo')),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SectionHeader('Palm enrollment'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(child: _palmCard('left', 'Left palm', _u.hasLeft)),
                        const SizedBox(width: 12),
                        Expanded(child: _palmCard('right', 'Right palm', _u.hasRight)),
                      ],
                    ),
                  ),
                  const SectionHeader('Identity'),
                  _pad(
                    TextFormField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Full name *',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (v) => (v == null || v.trim().length < 2) ? 'Enter a name' : null,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  _pad(
                    TextFormField(
                      controller: _code,
                      decoration: const InputDecoration(
                        labelText: 'Employee / member ID *',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter an ID' : null,
                    ),
                  ),
                  _pad(
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int?>(
                            initialValue: _u.departmentId,
                            decoration: const InputDecoration(labelText: 'Department'),
                            items: [
                              const DropdownMenuItem(value: null, child: Text('None')),
                              for (final d in _depts) DropdownMenuItem(value: d.id, child: Text(d.name)),
                            ],
                            onChanged: (v) => _u.departmentId = v,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<UserRole>(
                            initialValue: _u.role,
                            decoration: const InputDecoration(labelText: 'Role'),
                            items: [
                              for (final r in UserRole.values) DropdownMenuItem(value: r, child: Text(roleLabel(r))),
                            ],
                            onChanged: (v) => setState(() => _u.role = v!),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_u.role == UserRole.admin)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                      child: Text(
                        'Administrators can unlock the admin panel with their palm and are not limited by schedules.',
                        style: TextStyle(color: Brand.warning, fontSize: 12),
                      ),
                    ),
                  _pad(
                    TextFormField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: 'Phone', prefixIcon: Icon(Icons.phone_outlined)),
                    ),
                  ),
                  _pad(
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline)),
                      validator: (v) =>
                          (v == null || v.isEmpty || RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim()))
                          ? null
                          : 'Invalid email',
                    ),
                  ),
                  const SectionHeader('Access rules'),
                  SwitchListTile(
                    title: const Text('Account active'),
                    subtitle: Text(
                      _u.status == UserStatus.active ? 'Allowed to access' : 'Suspended — all access denied',
                    ),
                    value: _u.status == UserStatus.active,
                    onChanged: (v) => setState(() => _u.status = v ? UserStatus.active : UserStatus.suspended),
                  ),
                  _pad(
                    DropdownButtonFormField<int?>(
                      initialValue: _u.scheduleId,
                      decoration: const InputDecoration(
                        labelText: 'Access schedule',
                        prefixIcon: Icon(Icons.event_available_outlined),
                      ),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('No restriction')),
                        for (final s in _schedules)
                          DropdownMenuItem(value: s.id, child: Text('${s.name} (${s.summary})')),
                      ],
                      onChanged: (v) => _u.scheduleId = v,
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.play_circle_outline),
                    title: const Text('Valid from'),
                    subtitle: Text(_u.validFrom == null ? 'Immediately' : df.format(_u.validFrom!)),
                    trailing: _u.validFrom == null
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () => setState(() => _u.validFrom = null),
                          ),
                    onTap: () async {
                      final d = await _pickDate(_u.validFrom);
                      if (d != null) setState(() => _u.validFrom = d);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.stop_circle_outlined),
                    title: const Text('Valid until'),
                    subtitle: Text(_u.validUntil == null ? 'No expiry' : df.format(_u.validUntil!)),
                    trailing: _u.validUntil == null
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () => setState(() => _u.validUntil = null),
                          ),
                    onTap: () async {
                      final d = await _pickDate(_u.validUntil);
                      if (d != null) setState(() => _u.validUntil = DateTime(d.year, d.month, d.day, 23, 59, 59));
                    },
                  ),
                  _pad(
                    TextFormField(
                      controller: _qr,
                      decoration: InputDecoration(
                        labelText: 'QR pass code (optional fallback)',
                        prefixIcon: const Icon(Icons.qr_code_2),
                        suffixIcon: IconButton(
                          tooltip: 'Generate',
                          icon: const Icon(Icons.auto_awesome),
                          onPressed: () async => _qr.text =
                              'ATC-${(await DeviceBridge.instance.randomToken(12)).replaceAll(RegExp(r'[^A-Za-z0-9]'), '')}',
                        ),
                      ),
                    ),
                  ),
                  _pad(
                    TextFormField(
                      controller: _notes,
                      maxLines: 3,
                      decoration: const InputDecoration(labelText: 'Notes', alignLabelWithHint: true),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _pad(Widget w) => Padding(padding: const EdgeInsets.fromLTRB(16, 6, 16, 6), child: w);

  Widget _palmCard(String hand, String label, bool enrolled) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Transform.flip(
            flipX: hand == 'left',
            child: Icon(Icons.back_hand, size: 44, color: enrolled ? Brand.granted : Colors.black26),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(
            enrolled ? 'Enrolled' : 'Not enrolled',
            style: TextStyle(color: enrolled ? Brand.granted : Colors.black45, fontSize: 12),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: enrolled
                ? Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(onPressed: () => _enroll(hand), child: const Text('Redo')),
                      ),
                      const SizedBox(width: 6),
                      IconButton.outlined(onPressed: () => _removePalm(hand), icon: const Icon(Icons.delete_outline)),
                    ],
                  )
                : FilledButton.icon(
                    onPressed: () => _enroll(hand),
                    icon: const Icon(Icons.fingerprint),
                    label: const Text('Enroll'),
                  ),
          ),
        ],
      ),
    ),
  );
}
