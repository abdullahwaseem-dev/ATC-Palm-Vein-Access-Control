// Copyright (c) 2026 ATC. All rights reserved.
// Proprietary and confidential. Use, copying, modification or distribution without
// written permission from ATC is prohibited. See LICENSE in the repository root.

import 'dart:async';

import 'package:flutter/material.dart';

import '../core/auth.dart';
import '../core/bridges.dart';
import '../core/models.dart';
import '../core/services.dart';
import '../widgets/common.dart';

/// Guided palm capture. The SDK takes several good frames and returns one template.
class EnrollScreen extends StatefulWidget {
  final AppUser user;
  final String hand; // 'left' | 'right'
  const EnrollScreen({super.key, required this.user, required this.hand});
  @override
  State<EnrollScreen> createState() => _EnrollScreenState();
}

class _EnrollScreenState extends State<EnrollScreen> {
  StreamSubscription<PalmEvent>? _sub;
  late String _palmId;
  double _progress = 0;
  bool _palmIn = false;
  bool _done = false;
  bool _saving = false;
  String _message = 'Hold your open palm 5–10 cm above the scanner';
  String? _error;
  Timer? _tick;
  Timer? _messageReset;

  @override
  void initState() {
    super.initState();
    AuthService.instance.pauseTimeout(true);
    _palmId = PalmLibrary.newPalmId(widget.hand);
    _sub = PalmBridge.instance.events.listen(_onEvent);
    // Progress advances while a palm is in view (the SDK doesn't report capture count).
    _tick = Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (_palmIn && !_done && _progress < .92) setState(() => _progress += .025);
    });
    _start(const Duration(milliseconds: 800));
  }

  @override
  void dispose() {
    _sub?.cancel();
    _tick?.cancel();
    _messageReset?.cancel();
    PalmBridge.instance.stopCollect();
    AuthService.instance.pauseTimeout(false);
    super.dispose();
  }

  void _start([Duration delay = Duration.zero]) {
    Future.delayed(delay, () {
      if (!mounted || _done) return;
      setState(() {
        _progress = 0;
        _error = null;
      });
      PalmBridge.instance.startCollect(_palmId);
    });
  }

  void _say(String m, {bool error = false}) {
    _messageReset?.cancel();
    setState(() {
      if (error) {
        _error = m;
      } else {
        _message = m;
      }
    });
    if (error) {
      _messageReset = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _error = null);
      });
    }
  }

  Future<void> _onEvent(PalmEvent e) async {
    if (e.type != 'collect' || _done) return;
    switch (e.event) {
      case 'palmIn':
        if (!_palmIn) setState(() => _palmIn = true);
        _say('Hold still…');
      case 'palmNull':
        if (_palmIn) setState(() => _palmIn = false);
        _say('Hold your open palm 5–10 cm above the scanner');
      case 'success':
        final feature = e.data['feature'] as String?;
        if (feature == null || feature.isEmpty) {
          _say('Capture failed — try again', error: true);
          _start(const Duration(seconds: 2));
          return;
        }
        setState(() {
          _done = true;
          _saving = true;
          _progress = 1;
        });
        PalmBridge.instance.led('green');
        final err = await PalmLibrary.instance.saveTemplate(
          widget.user,
          widget.hand,
          _palmId,
          feature,
          actor: AuthService.instance.actor,
        );
        if (!mounted) return;
        if (err != null) {
          setState(() {
            _done = false;
            _saving = false;
          });
          _say(err, error: true);
          _palmId = PalmLibrary.newPalmId(widget.hand);
          _start(const Duration(seconds: 2));
          return;
        }
        setState(() => _saving = false);
        DeviceBridge.instance.tone('granted');
        await Future.delayed(const Duration(milliseconds: 900));
        if (mounted) Navigator.pop(context, true);
      case 'failure':
        final result = (e.data['result'] as int?) ?? 0;
        PalmBridge.instance.led('red');
        _say(PalmCodes.collectMessage(result, e.data['errorCode'] as int?), error: true);
        setState(() => _progress = 0);
        _start(const Duration(seconds: 2));
    }
  }

  @override
  Widget build(BuildContext context) {
    final left = widget.hand == 'left';
    final color = _error != null ? Brand.denied : (_done || _palmIn ? Brand.granted : const Color(0xFF8FA8E8));
    return Scaffold(
      backgroundColor: Brand.ink,
      appBar: AppBar(
        backgroundColor: Brand.ink,
        foregroundColor: Colors.white,
        title: Text('Enroll ${left ? 'left' : 'right'} palm', style: const TextStyle(color: Colors.white)),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) {
            final landscape = c.maxWidth > c.maxHeight;
            final preview = ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: color, width: 3),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const PalmPreview(),
                    ScanOverlay(color: color, active: !_done),
                    if (_done)
                      Container(
                        color: Brand.granted.withValues(alpha: .35),
                        child: Center(
                          child: _saving
                              ? const CircularProgressIndicator(color: Colors.white)
                              : const Icon(Icons.check_circle, color: Colors.white, size: 96),
                        ),
                      ),
                  ],
                ),
              ),
            );
            final info = Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    UserAvatar(user: widget.user, radius: 20),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        widget.user.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: 120,
                  height: 120,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox.expand(
                        child: CircularProgressIndicator(
                          value: _progress,
                          strokeWidth: 8,
                          color: color,
                          backgroundColor: Colors.white10,
                        ),
                      ),
                      Transform.flip(
                        flipX: left,
                        child: Icon(Icons.back_hand, color: color, size: 52),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Text(
                    _done ? 'Palm captured' : (_error ?? _message),
                    key: ValueKey(_done ? 'done' : (_error ?? _message)),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _error != null ? const Color(0xFFFCA5A5) : Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Use your ${left ? 'LEFT' : 'RIGHT'} hand · keep fingers slightly apart',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white54),
                ),
              ],
            );
            return Padding(
              padding: const EdgeInsets.all(20),
              child: landscape
                  ? Row(
                      children: [
                        Expanded(child: preview),
                        const SizedBox(width: 24),
                        Expanded(child: info),
                      ],
                    )
                  : Column(
                      children: [
                        Expanded(child: preview),
                        const SizedBox(height: 20),
                        info,
                      ],
                    ),
            );
          },
        ),
      ),
    );
  }
}
