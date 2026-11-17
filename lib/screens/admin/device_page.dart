// Copyright (c) 2026 ATC. All rights reserved.
// Proprietary and confidential. Use, copying, modification or distribution without
// written permission from ATC is prohibited. See LICENSE in the repository root.

import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/auth.dart';
import '../../core/bridges.dart';
import '../../core/db.dart';
import '../../core/services.dart';
import '../../core/settings.dart';
import '../../widgets/common.dart';
import '../calibration_screen.dart';

String hex4(int v) => '0x${v.toRadixString(16).toUpperCase().padLeft(4, '0')}';

class DevicePage extends StatefulWidget {
  const DevicePage({super.key});
  @override
  State<DevicePage> createState() => _DevicePageState();
}

class _DevicePageState extends State<DevicePage> {
  Map<String, dynamic> _status = {};
  Map<String, dynamic> _info = {};
  Map<String, int> _userStats = {};
  bool _busy = false;
  final _s = AppSettings.instance;
  String get _actor => AuthService.instance.actor;

  @override
  void initState() {
    super.initState();
    AppState.instance.addListener(_refresh);
    _refresh();
  }

  @override
  void dispose() {
    AppState.instance.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _refresh() async {
    final st = await PalmBridge.instance.status();
    final info = await DeviceBridge.instance.deviceInfo();
    final us = await AppDb.instance.userStats();
    if (mounted) {
      setState(() {
        _status = st;
        _info = info;
        _userStats = us;
      });
    }
  }

  Future<void> _applyCamera(Map<String, Object> values, String what) async {
    await _s.setMany(values);
    await _s.applyToEngine();
    await AppDb.instance.audit(_actor, 'Scanner settings changed', what);
    _refresh();
  }

  Future<void> _pickCamera(bool ir) async {
    final devices = await PalmBridge.instance.usbDevices();
    if (!mounted) return;
    final presets = ir
        ? [(0x1D6C, 0x0103, 'VP530 IR (type A)'), (0x0507, 0x0581, 'VP530 IR (type B)')]
        : [(0x2C7F, 0x4A60, 'VP530 RGB')];
    final picked = await showDialog<(int, int)>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text(ir ? 'Palm (IR) camera' : 'QR (RGB) camera'),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 4),
            child: Text('Detected USB devices', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          if (devices.isEmpty)
            const Padding(padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8), child: Text('None detected')),
          for (final d in devices)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, (d['vid'] as int, d['pid'] as int)),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(d['isCamera'] == true ? Icons.videocam_outlined : Icons.usb),
                title: Text('${d['name'] ?? 'USB device'}'),
                subtitle: Text(
                  '${hex4(d['vid'] as int)} : ${hex4(d['pid'] as int)}${d['manufacturer'] != null ? ' · ${d['manufacturer']}' : ''}',
                ),
              ),
            ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 4, 24, 4),
            child: Text('Known models', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          for (final p in presets)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, (p.$1, p.$2)),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(p.$3),
                subtitle: Text('${hex4(p.$1)} : ${hex4(p.$2)}'),
              ),
            ),
        ],
      ),
    );
    if (picked == null) return;
    await _applyCamera(
      ir ? {'ir_vid': picked.$1, 'ir_pid': picked.$2} : {'rgb_vid': picked.$1, 'rgb_pid': picked.$2},
      '${ir ? 'IR' : 'RGB'} camera ${hex4(picked.$1)}:${hex4(picked.$2)}',
    );
  }

  Future<void> _resync() async {
    setState(() => _busy = true);
    final (ok, fail) = await PalmLibrary.instance.resync();
    await AppDb.instance.audit(_actor, 'Palm library resynced', 'ok=$ok fail=$fail');
    setState(() => _busy = false);
    if (mounted) toast(context, 'Library rebuilt: $ok template(s)${fail > 0 ? ', $fail failed' : ''}', error: fail > 0);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final st = AppState.instance;
    final sdkCount = (_status['featureCount'] as int?) ?? -1;
    final dbCount = _userStats['palms'] ?? 0;
    final key = _status['deviceKey'] as String?;
    final extras = _status['hasLedAndCalibration'] != false; // Rockchip SDK has no LED/calibration API
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        const SectionHeader('Status'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(
                    st.ready ? Icons.check_circle : Icons.error_outline,
                    color: st.ready ? Brand.granted : Brand.denied,
                    size: 30,
                  ),
                  title: Text(st.statusLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(st.initMessage ?? 'VP530 palm-vein SDK'),
                  trailing: OutlinedButton(onPressed: () => PalmBridge.instance.reinit(), child: const Text('Restart')),
                ),
                const Divider(height: 1),
                _kv('Palm camera (IR)', st.irAttached ? 'Connected' : 'Not connected', ok: st.irAttached),
                if (_s.qrEnabled)
                  _kv('QR camera (RGB)', st.rgbAttached ? 'Connected' : 'Not connected', ok: st.rgbAttached),
                _kv('Templates in scanner', sdkCount < 0 ? '—' : '$sdkCount', ok: sdkCount < 0 || sdkCount == dbCount),
                _kv('Templates in database', '$dbCount'),
                _kv('Chipset build', '${_status['platform'] ?? '—'}'),
                _kv(
                  'Device',
                  '${_info['manufacturer'] ?? ''} ${_info['model'] ?? ''} · Android ${_info['android'] ?? ''}',
                ),
                _kv('App version', '${_info['appVersion'] ?? ''} (${_info['build'] ?? ''})'),
                if (key != null && key.isNotEmpty)
                  _kv(
                    'Device licence key',
                    key.length > 12 ? '${key.substring(0, 6)}…${key.substring(key.length - 4)}' : key,
                  ),
              ],
            ),
          ),
        ),
        const SectionHeader('Maintenance'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.sync),
                  title: const Text('Rebuild palm library'),
                  subtitle: const Text('Re-register every stored template in the scanner'),
                  trailing: _busy
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.chevron_right),
                  onTap: _busy || !st.ready ? null : _resync,
                ),
                if (extras)
                  ListTile(
                    leading: const Icon(Icons.tune),
                    title: const Text('Calibrate sensor'),
                    subtitle: const Text('Guided 3-step distance calibration'),
                    trailing: const Icon(Icons.chevron_right),
                    enabled: st.ready,
                    onTap: () =>
                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CalibrationScreen())),
                  ),
                if (extras)
                  ListTile(
                    leading: const Icon(Icons.lightbulb_outline),
                    title: const Text('Test indicator LED'),
                    trailing: Wrap(
                      spacing: 6,
                      children: [
                        for (final (c, col) in [
                          ('green', Brand.granted),
                          ('red', Brand.denied),
                          ('white', Colors.grey),
                        ])
                          ActionChip(
                            label: Text(c),
                            avatar: CircleAvatar(backgroundColor: col, radius: 6),
                            onPressed: () => PalmBridge.instance.led(c),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SectionHeader('Camera'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.sensors),
                  title: const Text('Palm (IR) camera'),
                  subtitle: Text('${hex4(_s.irVid)} : ${hex4(_s.irPid)}'),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => _pickCamera(true),
                ),
                ListTile(
                  leading: const Icon(Icons.qr_code_scanner),
                  title: const Text('QR (RGB) camera'),
                  subtitle: Text('${hex4(_s.rgbVid)} : ${hex4(_s.rgbPid)}'),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => _pickCamera(false),
                ),
                ListTile(
                  leading: const Icon(Icons.screen_rotation),
                  title: const Text('Preview rotation'),
                  trailing: DropdownButton<int>(
                    value: _s.rotation,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final r in [0, 90, 180, 270]) DropdownMenuItem(value: r, child: Text('$r°')),
                    ],
                    onChanged: (v) => _applyCamera({'rotation': v!}, 'rotation=$v'),
                  ),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.flip),
                  title: const Text('Mirror horizontally'),
                  value: _s.mirrorH,
                  onChanged: (v) => _applyCamera({'mirror_h': v}, 'mirrorH=$v'),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.flip_camera_android),
                  title: const Text('Mirror vertically'),
                  value: _s.mirrorV,
                  onChanged: (v) => _applyCamera({'mirror_v': v}, 'mirrorV=$v'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _kv(String k, String v, {bool? ok}) => ListTile(
    dense: true,
    title: Text(k),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (ok != null)
          Icon(ok ? Icons.check_circle : Icons.error, size: 16, color: ok ? Brand.granted : Brand.warning),
        const SizedBox(width: 6),
        Text(v, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
  );
}
