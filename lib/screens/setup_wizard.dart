// Copyright (c) 2026 ATC. All rights reserved.
// Proprietary and confidential. Use, copying, modification or distribution without
// written permission from ATC is prohibited. See LICENSE in the repository root.

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/auth.dart';
import '../core/db.dart';
import '../core/models.dart';
import '../core/settings.dart';
import '../widgets/common.dart';
import 'kiosk_screen.dart';

class SetupWizard extends StatefulWidget {
  const SetupWizard({super.key});
  @override
  State<SetupWizard> createState() => _SetupWizardState();
}

class _SetupWizardState extends State<SetupWizard> {
  int _step = 0;
  final _company = TextEditingController(text: 'ATC');
  final _terminal = TextEditingController(text: 'Main Entrance');
  final _pinKey = GlobalKey<PinPadState>();
  String? _firstPin;
  String? _pinError;
  TerminalMode _mode = TerminalMode.access;
  bool _busy = false;

  Future<void> _finish() async {
    setState(() => _busy = true);
    final db = AppDb.instance;
    if ((await db.schedules()).isEmpty) {
      await db.saveSchedule(AccessSchedule(name: 'Always (24/7)'));
      await db.saveSchedule(AccessSchedule(name: 'Office hours', days: 0x1F, startMinute: 420, endMinute: 1140));
    }
    if ((await db.departments()).isEmpty) await db.saveDepartment(Department(name: 'General'));
    await AppSettings.instance.setMany({
      'company_name': _company.text.trim().isEmpty ? 'ATC' : _company.text.trim(),
      'terminal_name': _terminal.text.trim().isEmpty ? 'Main Entrance' : _terminal.text.trim(),
      'mode': _mode.name,
      'setup_done': true,
    });
    await db.audit('setup', 'Terminal configured', 'terminal=${_terminal.text.trim()}');
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const KioskScreen()));
  }

  void _onPin(String pin) async {
    if (_firstPin == null) {
      if (!AuthService.isValidPin(pin)) {
        setState(() => _pinError = 'Use 6–8 digits; avoid repeated or sequential numbers.');
        _pinKey.currentState?.clear();
        return;
      }
      setState(() {
        _firstPin = pin;
        _pinError = null;
      });
      _pinKey.currentState?.clear();
    } else if (pin != _firstPin) {
      setState(() {
        _firstPin = null;
        _pinError = 'PINs did not match. Start again.';
      });
      _pinKey.currentState?.clear();
    } else {
      setState(() => _busy = true);
      await AuthService.instance.setPin(pin);
      setState(() {
        _busy = false;
        _step = 3;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final steps = [_welcome(), _identity(), _pin(), _modeStep(), _scanner()];
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Row(
                    children: [
                      const BrandLogo(height: 34),
                      const Spacer(),
                      Text('Step ${_step + 1} of ${steps.length}', style: Theme.of(context).textTheme.labelLarge),
                    ],
                  ),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(value: (_step + 1) / steps.length, borderRadius: BorderRadius.circular(4)),
                  const SizedBox(height: 24),
                  Expanded(child: SingleChildScrollView(child: steps[_step])),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _title(String t, String sub) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(t, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      Text(sub, style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.black54)),
      const SizedBox(height: 24),
    ],
  );

  Widget _welcome() => Column(
    children: [
      const SizedBox(height: 24),
      const BrandMark(size: 120),
      const SizedBox(height: 28),
      Text('ATC Palm Access', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      const Text(
        'Contactless palm-vein access control and attendance.\nAll biometric data stays encrypted on this device.',
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 40),
      SizedBox(
        width: double.infinity,
        child: FilledButton(onPressed: () => setState(() => _step = 1), child: const Text('Get started')),
      ),
    ],
  );

  Widget _identity() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _title('Terminal identity', 'Shown on the terminal screen and in reports.'),
      TextField(
        controller: _company,
        decoration: const InputDecoration(labelText: 'Company name', prefixIcon: Icon(Icons.business)),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _terminal,
        decoration: const InputDecoration(
          labelText: 'Terminal / door name',
          prefixIcon: Icon(Icons.door_front_door_outlined),
        ),
      ),
      const SizedBox(height: 32),
      FilledButton(onPressed: () => setState(() => _step = 2), child: const Text('Continue')),
    ],
  );

  Widget _pin() => Column(
    children: [
      _title(
        _firstPin == null ? 'Create admin PIN' : 'Confirm admin PIN',
        'The PIN protects the admin panel. It is stored as a salted, hardware-key-protected hash.',
      ),
      if (_pinError != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(_pinError!, style: const TextStyle(color: Brand.denied)),
        ),
      _busy
          ? const Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator())
          : PinPad(key: _pinKey, onSubmit: _onPin),
    ],
  );

  Widget _modeStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _title('Terminal mode', 'You can change this later in Settings.'),
      for (final (m, icon, title, sub) in [
        (TerminalMode.access, Icons.lock_open, 'Access control', 'Grant or deny entry at a door.'),
        (
          TerminalMode.attendance,
          Icons.schedule,
          'Attendance',
          'Record check-in and check-out with working-hours reports.',
        ),
      ])
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: _mode == m ? Brand.blue : const Color(0xFFE4E8F0), width: _mode == m ? 2 : 1),
            ),
            child: ListTile(
              onTap: () => setState(() => _mode = m),
              leading: Icon(icon, color: Brand.blue),
              title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(sub),
              trailing: Icon(_mode == m ? Icons.radio_button_checked : Icons.radio_button_off, color: Brand.blue),
            ),
          ),
        ),
      const SizedBox(height: 20),
      FilledButton(onPressed: () => setState(() => _step = 4), child: const Text('Continue')),
    ],
  );

  Widget _scanner() => ListenableBuilder(
    listenable: AppState.instance,
    builder: (context, _) {
      final st = AppState.instance;
      final color = st.ready ? Brand.granted : (st.initState == 'initializing' ? Brand.warning : Brand.denied);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _title('Scanner check', 'The VP530 palm module connects over USB.'),
          Card(
            child: ListTile(
              leading: Icon(st.ready ? Icons.check_circle : Icons.sensors, color: color, size: 32),
              title: Text(st.statusLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                st.initMessage ??
                    (st.ready
                        ? 'Ready to enroll and recognise palms.'
                        : 'You can finish setup now and connect the scanner later.'),
              ),
            ),
          ),
          const SizedBox(height: 32),
          FilledButton(onPressed: _busy ? null : _finish, child: const Text('Finish setup')),
        ],
      );
    },
  );
}
