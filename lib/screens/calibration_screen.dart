// Copyright (c) 2026 ATC. All rights reserved.
// Proprietary and confidential. Use, copying, modification or distribution without
// written permission from ATC is prohibited. See LICENSE in the repository root.

import 'dart:async';

import 'package:flutter/material.dart';

import '../core/auth.dart';
import '../core/bridges.dart';
import '../core/db.dart';
import '../widgets/common.dart';

/// Three-step distance calibration (no hand → near → far), ported from the vendor demo.
class CalibrationScreen extends StatefulWidget {
  const CalibrationScreen({super.key});
  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen> {
  static const _steps = [
    ('Remove your hand', 'Keep the area above the scanner completely clear.', Icons.do_not_touch_outlined),
    ('Hand close', 'Hold your open palm about 5 cm above the scanner.', Icons.back_hand),
    ('Hand far', 'Hold your open palm about 15 cm above the scanner.', Icons.pan_tool_outlined),
  ];
  int _step = 0; // 0..2 sampling, 3 = ready to calibrate, 4 = done
  int _progress = 0;
  bool _busy = false;
  String? _error;
  final _samples = <List<int>>[[], [], []];
  StreamSubscription<PalmEvent>? _sub;

  @override
  void initState() {
    super.initState();
    AuthService.instance.pauseTimeout(true);
    _sub = PalmBridge.instance.events.listen((e) {
      if (e.type == 'calibration' && mounted) setState(() => _progress = e.data['progress'] as int);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    AuthService.instance.pauseTimeout(false);
    super.dispose();
  }

  Future<void> _sample() async {
    setState(() {
      _busy = true;
      _error = null;
      _progress = 0;
    });
    try {
      final (values, verdict) = await PalmBridge.instance.calibrationSample(_step + 1);
      if (verdict == 'OK') {
        _samples[_step] = values;
        setState(() => _step++);
      } else {
        setState(
          () => _error = verdict == 'UNSTABLE'
              ? 'Readings were unstable. Keep your hand still and try again.'
              : 'Readings were invalid. Check the position and try again.',
        );
      }
    } catch (e) {
      setState(() => _error = 'Sampling failed: $e');
    }
    setState(() => _busy = false);
  }

  Future<void> _calibrate() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await PalmBridge.instance.calibrate(_samples[0], _samples[1], _samples[2]);
      if (r == 'OK') {
        await AppDb.instance.audit(AuthService.instance.actor, 'Sensor calibrated');
        setState(() => _step = 4);
        await PalmBridge.instance.reinit();
      } else {
        setState(() {
          _error = r == 'ORDER_VIOLATION'
              ? 'Distances were out of order (close must read higher than far). Start again.'
              : 'Calibration data incomplete. Start again.';
          _step = 0;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Calibration failed: $e';
        _step = 0;
      });
    }
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sensor calibration')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_step < 4)
              AspectRatio(
                aspectRatio: 4 / 3,
                child: ClipRRect(borderRadius: BorderRadius.circular(20), child: const PalmPreview()),
              ),
            const SizedBox(height: 20),
            for (var i = 0; i < 3; i++)
              Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: i < _step ? Brand.granted : (i == _step ? Brand.blue : Colors.black12),
                    child: i < _step
                        ? const Icon(Icons.check, color: Colors.white)
                        : Icon(_steps[i].$3, color: i == _step ? Colors.white : Colors.black45),
                  ),
                  title: Text('Step ${i + 1}: ${_steps[i].$1}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(_steps[i].$2),
                  trailing: i == _step && _busy
                      ? SizedBox(width: 44, child: Text('$_progress%', textAlign: TextAlign.end))
                      : null,
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_error!, style: const TextStyle(color: Brand.denied)),
              ),
            const SizedBox(height: 12),
            if (_step < 3)
              FilledButton.icon(
                onPressed: _busy ? null : _sample,
                icon: const Icon(Icons.play_arrow),
                label: Text(_busy ? 'Sampling…' : 'Start step ${_step + 1}'),
              )
            else if (_step == 3)
              FilledButton.icon(
                onPressed: _busy ? null : _calibrate,
                icon: const Icon(Icons.tune),
                label: Text(_busy ? 'Calibrating…' : 'Apply calibration'),
              )
            else
              Column(
                children: [
                  const Icon(Icons.verified, color: Brand.granted, size: 72),
                  const SizedBox(height: 12),
                  const Text('Calibration complete', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
