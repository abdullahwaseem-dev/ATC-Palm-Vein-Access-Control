// Copyright (c) 2026 ATC. All rights reserved.
// Proprietary and confidential. Use, copying, modification or distribution without
// written permission from ATC is prohibited. See LICENSE in the repository root.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/auth.dart';
import '../../core/backup.dart';
import '../../core/bridges.dart';
import '../../core/db.dart';
import '../../core/services.dart';
import '../../core/settings.dart';
import '../../widgets/common.dart';
import '../setup_wizard.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _s = AppSettings.instance;
  bool _launcher = false;
  String get _actor => AuthService.instance.actor;

  @override
  void initState() {
    super.initState();
    _s.addListener(_changed);
    DeviceBridge.instance.isLauncherMode().then((v) => mounted ? setState(() => _launcher = v) : null);
  }

  @override
  void dispose() {
    _s.removeListener(_changed);
    super.dispose();
  }

  void _changed() => mounted ? setState(() {}) : null;

  Future<void> _set(String key, Object value, {bool engine = false, bool audit = true}) async {
    await _s.set(key, value);
    if (engine) await _s.applyToEngine();
    if (audit) await AppDb.instance.audit(_actor, 'Setting changed', '$key=${key.contains('secret') ? '***' : value}');
  }

  Future<String?> _text(
    String title,
    String initial, {
    String? hint,
    String? Function(String)? validate,
    bool obscure = false,
  }) async {
    final ctl = TextEditingController(text: initial);
    String? err;
    return showDialog<String>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: ctl,
            autofocus: true,
            obscureText: obscure,
            decoration: InputDecoration(hintText: hint, errorText: err),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final v = ctl.text.trim();
                final e = validate?.call(v);
                if (e != null) {
                  set(() => err = e);
                } else {
                  Navigator.pop(c, v);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _changePin() async {
    final current = await _text('Current PIN', '', obscure: true);
    if (current == null) return;
    if (!await DeviceBridge.instance.verifyPin(current, _s.adminPinHash)) {
      await AppDb.instance.audit(_actor, 'PIN change refused', 'wrong current PIN');
      if (mounted) toast(context, 'Current PIN is incorrect', error: true);
      return;
    }
    final pin = await _text(
      'New PIN (6–8 digits)',
      '',
      obscure: true,
      validate: (v) => AuthService.isValidPin(v) ? null : 'Use 6–8 digits; avoid 123456 / 000000',
    );
    if (pin == null) return;
    final again = await _text(
      'Confirm new PIN',
      '',
      obscure: true,
      validate: (v) => v == pin ? null : 'PINs do not match',
    );
    if (again == null) return;
    await AuthService.instance.setPin(pin, by: _actor);
    if (mounted) toast(context, 'Admin PIN updated');
  }

  Future<String?> _backupPassword({required bool create}) async {
    final pw = await _text(
      create ? 'Backup password' : 'Backup password',
      '',
      obscure: true,
      hint: create ? 'At least 10 characters, letters + numbers' : null,
      validate: create ? BackupService.validatePassword : (v) => v.isEmpty ? 'Required' : null,
    );
    if (pw == null || !create) return pw;
    final again = await _text(
      'Confirm password',
      '',
      obscure: true,
      validate: (v) => v == pw ? null : 'Passwords do not match',
    );
    return again;
  }

  Future<void> _export() async {
    final includeLogs = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Create encrypted backup'),
        content: const Text(
          'The backup contains users and palm templates, encrypted with a password you choose. '
          'Store the file and password separately. Without the password the file cannot be restored.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          OutlinedButton(onPressed: () => Navigator.pop(c, false), child: const Text('Without logs')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Include logs')),
        ],
      ),
    );
    if (includeLogs == null) return;
    final pw = await _backupPassword(create: true);
    if (pw == null) return;
    AuthService.instance.pauseTimeout(true);
    try {
      final msg = await BackupService.instance.exportBackup(pw, includeLogs: includeLogs, actor: _actor);
      if (msg != null && mounted) toast(context, msg);
    } catch (e) {
      if (mounted) toast(context, 'Backup failed: $e', error: true);
    } finally {
      AuthService.instance.pauseTimeout(false);
    }
  }

  Future<void> _restore() async {
    final pw = await _backupPassword(create: false);
    if (pw == null) return;
    AuthService.instance.pauseTimeout(true);
    try {
      final data = await BackupService.instance.readBackup(pw);
      if (data == null || !mounted) return;
      final n = (data['users'] as List).length;
      if (!await confirm(
        context,
        'Restore backup?',
        'This replaces ALL users, palm templates, schedules and logs on this terminal with the backup from '
            '"${data['terminal']}" ($n users). This cannot be undone.',
        ok: 'Restore',
        destructive: true,
      )) {
        return;
      }
      final msg = await BackupService.instance.restore(data, actor: _actor);
      if (mounted) toast(context, msg);
    } on FormatException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } catch (e) {
      if (mounted) toast(context, 'Wrong password or damaged file', error: true);
    } finally {
      AuthService.instance.pauseTimeout(false);
    }
  }

  Future<void> _factoryReset() async {
    if (!await confirm(
      context,
      'Factory reset?',
      'Deletes every user, palm template, photo, log and setting on this terminal. Make a backup first.',
      ok: 'Erase everything',
      destructive: true,
    )) {
      return;
    }
    final typed = await _text('Type ERASE to confirm', '', validate: (v) => v == 'ERASE' ? null : 'Type ERASE');
    if (typed != 'ERASE') return;
    await BackupService.instance.factoryReset();
    final photos = Directory(p.join((await getApplicationSupportDirectory()).path, 'photos'));
    if (await photos.exists()) await photos.delete(recursive: true);
    await DeviceBridge.instance.stopKiosk();
    await AuthService.instance.logout(reason: 'factory reset');
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const SetupWizard()), (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 40),
      children: [
        const SectionHeader('Terminal'),
        _card([
          ListTile(
            leading: const Icon(Icons.business),
            title: const Text('Company name'),
            subtitle: Text(_s.companyName),
            onTap: () async {
              final v = await _text('Company name', _s.companyName);
              if (v != null && v.isNotEmpty) _set('company_name', v);
            },
          ),
          ListTile(
            leading: const Icon(Icons.door_front_door_outlined),
            title: const Text('Terminal name'),
            subtitle: Text(_s.terminalName),
            onTap: () async {
              final v = await _text('Terminal name', _s.terminalName);
              if (v != null && v.isNotEmpty) _set('terminal_name', v);
            },
          ),
          ListTile(
            leading: const Icon(Icons.waving_hand_outlined),
            title: const Text('Greeting'),
            subtitle: Text(_s.welcomeText),
            onTap: () async {
              final v = await _text('Greeting', _s.welcomeText);
              if (v != null && v.isNotEmpty) _set('welcome_text', v);
            },
          ),
          ListTile(
            leading: const Icon(Icons.swap_horiz),
            title: const Text('Mode'),
            trailing: SegmentedButton<TerminalMode>(
              segments: const [
                ButtonSegment(value: TerminalMode.access, label: Text('Access')),
                ButtonSegment(value: TerminalMode.attendance, label: Text('Attendance')),
              ],
              selected: {_s.mode},
              onSelectionChanged: (v) => _set('mode', v.first.name),
            ),
          ),
          _slider(
            Icons.timer_outlined,
            'Result display time',
            '${_s.resultSeconds}s',
            _s.resultSeconds,
            1,
            10,
            (v) => _set('result_seconds', v, audit: false),
          ),
          _slider(
            Icons.repeat,
            'Ignore repeat scans for',
            '${_s.duplicateSeconds}s',
            _s.duplicateSeconds,
            0,
            300,
            (v) => _set('duplicate_seconds', v, audit: false),
            divisions: 30,
          ),
        ]),
        const SectionHeader('Feedback & privacy'),
        _card([
          _switch(Icons.record_voice_over_outlined, 'Voice greeting', _s.voiceEnabled, (v) => _set('voice', v)),
          _switch(Icons.volume_up_outlined, 'Beep', _s.beepEnabled, (v) => _set('beep', v)),
          _switch(Icons.account_box_outlined, 'Show photo on result', _s.showPhoto, (v) => _set('show_photo', v)),
          _switch(
            Icons.visibility_off_outlined,
            'Privacy: first name only on screen',
            _s.privacyNames,
            (v) => _set('privacy_names', v),
            sub: 'Hides surnames and departments from bystanders',
          ),
          _switch(Icons.analytics_outlined, 'Show match score', _s.showScore, (v) => _set('show_score', v)),
        ]),
        const SectionHeader('Recognition'),
        _card([
          _slider(
            Icons.security,
            'Match threshold',
            '${_s.threshold}',
            _s.threshold,
            55,
            90,
            (v) => _set('threshold', v, engine: true),
            divisions: 35,
            sub: 'Higher = stricter (fewer false accepts, more retries). Default 65.',
          ),
          _switch(
            Icons.qr_code_scanner,
            'QR pass fallback (RGB camera)',
            _s.qrEnabled,
            (v) => _set('qr_enabled', v, engine: true),
            sub: 'Users with a QR code can scan it instead of their palm. Lower security than palm.',
          ),
        ]),
        const SectionHeader('Security'),
        _card([
          ListTile(
            leading: const Icon(Icons.password),
            title: const Text('Change admin PIN'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _changePin,
          ),
          _switch(
            Icons.back_hand_outlined,
            'Admin palm unlock',
            _s.adminPalmUnlock,
            (v) => _set('admin_palm_unlock', v),
            sub: 'Users with the Administrator role can open this panel with their palm',
          ),
          _slider(
            Icons.lock_clock,
            'Auto-lock admin panel after',
            '${_s.autoLockMinutes} min',
            _s.autoLockMinutes,
            1,
            15,
            (v) => _set('auto_lock_minutes', v),
          ),
          _slider(
            Icons.pin_outlined,
            'PIN attempts before lockout',
            '${_s.maxPinAttempts}',
            _s.maxPinAttempts,
            3,
            10,
            (v) => _set('max_pin_attempts', v),
          ),
          _switch(
            Icons.screen_lock_portrait,
            'Kiosk lock (screen pinning)',
            _s.kioskLock,
            (v) async {
              await _set('kiosk_lock', v);
              v ? await DeviceBridge.instance.startKiosk() : await DeviceBridge.instance.stopKiosk();
            },
            sub: 'Blocks Home/Recents so users cannot leave the app',
          ),
          _switch(
            Icons.home_outlined,
            'Dedicated device (set as home app)',
            _launcher,
            (v) async {
              await DeviceBridge.instance.setLauncherMode(v);
              await AppDb.instance.audit(_actor, 'Setting changed', 'launcher_mode=$v');
              if (!mounted) return;
              setState(() => _launcher = v);
              if (v) {
                toast(this.context, 'Choose "ATC Palm Access" as the default home app');
                await DeviceBridge.instance.openHomeSettings();
              }
            },
            sub: 'App starts at boot and replaces the Android home screen',
          ),
          _switch(Icons.power_settings_new, 'Start on boot', _s.bootStart, (v) async {
            await _set('boot_start', v);
            await DeviceBridge.instance.setBootStart(v);
          }),
        ]),
        const SectionHeader('Integration (webhook)'),
        _card([
          ListTile(
            leading: const Icon(Icons.webhook),
            title: const Text('Webhook URL'),
            subtitle: Text(_s.webhookUrl.isEmpty ? 'Not set — events stay on this device' : _s.webhookUrl),
            onTap: () async {
              final v = await _text(
                'Webhook URL (https only)',
                _s.webhookUrl,
                hint: 'https://example.com/hooks/access',
                validate: WebhookService.validateUrl,
              );
              if (v != null) _set('webhook_url', v);
            },
          ),
          ListTile(
            leading: const Icon(Icons.key),
            title: const Text('Signing secret'),
            subtitle: Text(
              _s.webhookSecret.isEmpty ? 'Not set (requests unsigned)' : 'Set · HMAC-SHA256 in X-ATC-Signature',
            ),
            trailing: TextButton(
              onPressed: () async {
                final secret = await DeviceBridge.instance.randomToken(32);
                await _set('webhook_secret', await DeviceBridge.instance.encrypt(secret)); // Keystore-encrypted at rest
                if (!mounted) return;
                await showDialog(
                  context: this.context,
                  builder: (c) => AlertDialog(
                    title: const Text('New signing secret'),
                    content: SelectableText(
                      'Copy this into the receiving system. It will not be shown again.\n\n$secret',
                    ),
                    actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Done'))],
                  ),
                );
              },
              child: const Text('Generate'),
            ),
          ),
          _switch(
            Icons.gpp_bad_outlined,
            'Also send denied attempts',
            _s.webhookOnDenied,
            (v) => _set('webhook_denied', v),
          ),
          ListTile(
            leading: const Icon(Icons.send_outlined),
            title: const Text('Send test event'),
            enabled: _s.webhookUrl.isNotEmpty,
            onTap: () async {
              final err = await WebhookService.instance.send(
                AccessDecision(granted: true, reason: 'granted', method: 'test'),
                test: true,
              );
              if (context.mounted) toast(context, err == null ? 'Test delivered' : 'Failed: $err', error: err != null);
            },
          ),
        ]),
        const SectionHeader('Data'),
        _card([
          ListTile(
            leading: const Icon(Icons.auto_delete_outlined),
            title: const Text('Keep access records for'),
            trailing: DropdownButton<int>(
              value: const [30, 90, 180, 365, 730, 0].contains(_s.logRetentionDays) ? _s.logRetentionDays : 365,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: 30, child: Text('30 days')),
                DropdownMenuItem(value: 90, child: Text('90 days')),
                DropdownMenuItem(value: 180, child: Text('6 months')),
                DropdownMenuItem(value: 365, child: Text('1 year')),
                DropdownMenuItem(value: 730, child: Text('2 years')),
                DropdownMenuItem(value: 0, child: Text('Forever')),
              ],
              onChanged: (v) => _set('log_retention_days', v!),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.backup_outlined),
            title: const Text('Create encrypted backup'),
            onTap: _export,
          ),
          ListTile(leading: const Icon(Icons.restore), title: const Text('Restore from backup'), onTap: _restore),
          ListTile(
            leading: const Icon(Icons.delete_sweep_outlined),
            title: const Text('Clear access records'),
            onTap: () async {
              if (!await confirm(
                context,
                'Clear all access records?',
                'Users and palms are kept.',
                ok: 'Clear',
                destructive: true,
              )) {
                return;
              }
              final n = await AppDb.instance.clearLogs();
              await AppDb.instance.audit(_actor, 'Access records cleared', '$n records');
              if (context.mounted) toast(context, '$n records deleted');
            },
          ),
          ListTile(
            leading: const Icon(Icons.warning_amber, color: Brand.denied),
            title: const Text('Factory reset', style: TextStyle(color: Brand.denied)),
            onTap: _factoryReset,
          ),
        ]),
      ],
    );
  }

  Widget _card(List<Widget> children) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Card(child: Column(children: children)),
  );

  Widget _switch(IconData icon, String title, bool value, ValueChanged<bool> onChanged, {String? sub}) =>
      SwitchListTile(
        secondary: Icon(icon),
        title: Text(title),
        subtitle: sub == null ? null : Text(sub),
        value: value,
        onChanged: onChanged,
      );

  Widget _slider(
    IconData icon,
    String title,
    String label,
    int value,
    int min,
    int max,
    ValueChanged<int> onChanged, {
    int? divisions,
    String? sub,
  }) => _SettingSlider(
    key: ValueKey(title),
    icon: icon,
    title: title,
    value: value,
    min: min,
    max: max,
    divisions: divisions,
    sub: sub,
    onChanged: onChanged,
    format: (v) => label.replaceFirst('$value', '$v'),
  );
}

class _SettingSlider extends StatefulWidget {
  final IconData icon;
  final String title;
  final String? sub;
  final int value, min, max;
  final int? divisions;
  final ValueChanged<int> onChanged;
  final String Function(int) format;
  const _SettingSlider({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.format,
    this.divisions,
    this.sub,
  });
  @override
  State<_SettingSlider> createState() => _SettingSliderState();
}

class _SettingSliderState extends State<_SettingSlider> {
  late double _v = widget.value.clamp(widget.min, widget.max).toDouble();
  @override
  void didUpdateWidget(_SettingSlider old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _v = widget.value.clamp(widget.min, widget.max).toDouble();
  }

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(widget.icon),
    title: Row(
      children: [
        Expanded(child: Text(widget.title)),
        Text(widget.format(_v.round()), style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    ),
    subtitle: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.sub != null) Text(widget.sub!),
        Slider(
          value: _v,
          min: widget.min.toDouble(),
          max: widget.max.toDouble(),
          divisions: widget.divisions ?? (widget.max - widget.min),
          onChanged: (v) => setState(() => _v = v),
          onChangeEnd: (v) => widget.onChanged(v.round()),
        ),
      ],
    ),
  );
}
