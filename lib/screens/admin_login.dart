// Copyright (c) 2026 ATC. All rights reserved.
// Proprietary and confidential. Use, copying, modification or distribution without
// written permission from ATC is prohibited. See LICENSE in the repository root.

import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/auth.dart';
import '../core/bridges.dart';
import '../core/db.dart';
import '../core/models.dart';
import '../core/settings.dart';
import '../widgets/common.dart';
import 'admin/admin_shell.dart';

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});
  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _pinKey = GlobalKey<PinPadState>();
  String? _error;
  bool _busy = false;
  bool _palmMode = false;
  StreamSubscription<PalmEvent>? _sub;
  Timer? _lockTicker;
  Timer? _idle;

  bool get _palmAvailable => AppSettings.instance.adminPalmUnlock && AppState.instance.ready;

  @override
  void initState() {
    super.initState();
    _sub = PalmBridge.instance.events.listen(_onEvent);
    _lockTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (AuthService.instance.lockoutRemaining() != null && mounted) setState(() {});
    });
    // Abandoned login screen returns to the terminal.
    _idle = Timer(const Duration(seconds: 60), () {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _lockTicker?.cancel();
    _idle?.cancel();
    PalmBridge.instance.stopRecognize();
    super.dispose();
  }

  Future<void> _enterAdmin() async {
    if (!mounted) return;
    await PalmBridge.instance.stopRecognize();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const AdminShell()));
  }

  Future<void> _onPin(String pin) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await AuthService.instance.loginWithPin(pin);
    if (!mounted) return;
    setState(() => _busy = false);
    _pinKey.currentState?.clear();
    if (err == null) {
      await _enterAdmin();
    } else {
      setState(() => _error = err);
    }
  }

  void _setPalmMode(bool v) {
    setState(() {
      _palmMode = v;
      _error = null;
    });
    if (v) {
      Future.delayed(const Duration(milliseconds: 700), () {
        if (mounted && _palmMode) PalmBridge.instance.startRecognize();
      });
    } else {
      PalmBridge.instance.stopRecognize();
    }
  }

  Future<void> _onEvent(PalmEvent e) async {
    if (!_palmMode || e.type != 'recognize') return;
    if (e.event == 'success') {
      final user = await AppDb.instance.userByPalmId(e.data['palmId'] as String);
      final now = DateTime.now();
      final valid =
          user != null &&
          (user.validFrom == null || !now.isBefore(user.validFrom!)) &&
          (user.validUntil == null || !now.isAfter(user.validUntil!));
      if (user != null && valid && user.role == UserRole.admin && user.status == UserStatus.active) {
        PalmBridge.instance.led('green');
        await AuthService.instance.loginWithPalm(user.name);
        await _enterAdmin();
        return;
      }
      PalmBridge.instance.led('red');
      await AppDb.instance.audit(user?.name ?? 'unknown', 'Admin palm login refused', 'not an active administrator');
      if (mounted) {
        setState(() => _error = user == null ? 'Palm not recognised.' : '${user.name} is not an administrator.');
      }
    } else if (e.event == 'failure' && (e.data['result'] as int?) == PalmCodes.identifyLowScore) {
      PalmBridge.instance.led('red');
      if (mounted) setState(() => _error = 'Palm not recognised.');
    } else if (e.event != 'failure') {
      return;
    }
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted && _palmMode) PalmBridge.instance.startRecognize();
    });
  }

  @override
  Widget build(BuildContext context) {
    final lock = AuthService.instance.lockoutRemaining();
    return Scaffold(
      backgroundColor: Brand.ink,
      appBar: AppBar(
        backgroundColor: Brand.ink,
        foregroundColor: Colors.white,
        title: const Text('Administrator', style: TextStyle(color: Colors.white)),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                children: [
                  const Icon(Icons.shield_outlined, color: Color(0xFF8FA8E8), size: 48),
                  const SizedBox(height: 12),
                  Text(
                    _palmMode ? 'Scan an administrator palm' : 'Enter admin PIN',
                    style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 20),
                  if (_palmAvailable)
                    SegmentedButton<bool>(
                      style: SegmentedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        selectedForegroundColor: Colors.white,
                        selectedBackgroundColor: Brand.blue,
                        side: const BorderSide(color: Colors.white24),
                      ),
                      segments: const [
                        ButtonSegment(value: false, label: Text('PIN'), icon: Icon(Icons.dialpad)),
                        ButtonSegment(value: true, label: Text('Palm'), icon: Icon(Icons.back_hand_outlined)),
                      ],
                      selected: {_palmMode},
                      onSelectionChanged: (v) => _setPalmMode(v.first),
                    ),
                  const SizedBox(height: 20),
                  if (_error != null || lock != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Text(
                        lock != null ? 'Locked. Try again in ${lock.inSeconds + 1}s.' : _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 15),
                      ),
                    ),
                  if (_palmMode)
                    AspectRatio(
                      aspectRatio: 3 / 4,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: const Stack(fit: StackFit.expand, children: [PalmPreview(), ScanOverlay()]),
                      ),
                    )
                  else if (_busy)
                    const Padding(padding: EdgeInsets.all(60), child: CircularProgressIndicator())
                  else
                    PinPad(key: _pinKey, dark: true, enabled: lock == null, onSubmit: _onPin),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
