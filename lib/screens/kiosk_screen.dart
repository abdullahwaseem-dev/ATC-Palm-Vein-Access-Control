// Copyright (c) 2026 ATC. All rights reserved.
// Proprietary and confidential. Use, copying, modification or distribution without
// written permission from ATC is prohibited. See LICENSE in the repository root.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/app_state.dart';
import '../core/bridges.dart';
import '../core/models.dart';
import '../core/services.dart';
import '../core/settings.dart';
import '../widgets/common.dart';
import 'admin_login.dart';

/// The always-on terminal screen: live palm recognition and access result display.
class KioskScreen extends StatefulWidget {
  const KioskScreen({super.key});
  @override
  State<KioskScreen> createState() => _KioskScreenState();
}

class _KioskScreenState extends State<KioskScreen> with RouteAware, WidgetsBindingObserver {
  final _settings = AppSettings.instance;
  final _state = AppState.instance;
  StreamSubscription<PalmEvent>? _sub;
  Timer? _resultTimer;
  Timer? _restartTimer;
  bool _covered = false;
  bool _handling = false;
  bool _palmIn = false;
  AccessDecision? _decision;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable().catchError((_) {});
    _sub = PalmBridge.instance.events.listen(_onEvent);
    _state.addListener(_onState);
    _settings.addListener(_onSettings);
    if (_settings.kioskLock) DeviceBridge.instance.startKiosk();
    _scheduleStart();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) routeObserver.subscribe(this, route);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _state.removeListener(_onState);
    _settings.removeListener(_onSettings);
    _resultTimer?.cancel();
    _restartTimer?.cancel();
    PalmBridge.instance.stopRecognize();
    super.dispose();
  }

  // Another screen (admin) covers this one: release the camera so it can use it.
  @override
  void didPushNext() {
    PalmBridge.instance.stopRecognize();
    setState(() => _covered = true);
  }

  @override
  void didPopNext() {
    setState(() {
      _covered = false;
      _decision = null;
      _handling = false;
    });
    WakelockPlus.enable().catchError((_) {});
    _scheduleStart();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed && !_covered) _scheduleStart();
  }

  void _onState() {
    if (mounted) setState(() {});
    if (_state.ready) _scheduleStart();
  }

  void _onSettings() {
    if (mounted) setState(() {});
  }

  void _scheduleStart([Duration delay = const Duration(milliseconds: 600)]) {
    _restartTimer?.cancel();
    _restartTimer = Timer(delay, () {
      if (!mounted || _covered || _decision != null || !_state.ready) return;
      _handling = false;
      PalmBridge.instance.startRecognize();
    });
  }

  Future<void> _onEvent(PalmEvent e) async {
    if (_covered || !mounted) return;
    if (e.type == 'recognize') {
      switch (e.event) {
        case 'palmIn':
          if (!_palmIn) setState(() => _palmIn = true);
        case 'palmNull':
          if (_palmIn) setState(() => _palmIn = false);
        case 'success':
          if (_handling) return;
          _handling = true;
          _show(await AccessEngine.instance.onPalm(e.data['palmId'] as String, (e.data['score'] as int?) ?? 0));
        case 'failure':
          final result = e.data['result'] as int?;
          if (result == PalmCodes.identifyLowScore && !_handling) {
            _handling = true;
            _show(await AccessEngine.instance.onUnknownPalm((e.data['score'] as int?) ?? 0));
          } else {
            _scheduleStart(const Duration(milliseconds: 400)); // timeout / no palm: keep scanning
          }
      }
    } else if (e.type == 'qr') {
      if (_handling) return;
      _handling = true;
      await PalmBridge.instance.stopRecognize();
      _show(await AccessEngine.instance.onQr(e.data['text'] as String));
    }
  }

  void _show(AccessDecision d) {
    if (!mounted) return;
    setState(() {
      _decision = d;
      _palmIn = false;
    });
    AccessEngine.instance.feedback(d);
    _resultTimer?.cancel();
    _resultTimer = Timer(Duration(seconds: _settings.resultSeconds.clamp(1, 15)), () {
      if (!mounted) return;
      setState(() => _decision = null);
      PalmBridge.instance.led('white');
      _scheduleStart(const Duration(milliseconds: 300));
    });
  }

  Future<void> _openAdmin() async {
    await PalmBridge.instance.stopRecognize();
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminLoginScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Brand.ink,
        body: Stack(
          children: [
            SafeArea(
              child: LayoutBuilder(
                builder: (context, c) {
                  final landscape = c.maxWidth > c.maxHeight * 1.15;
                  final preview = _previewCard();
                  final info = _infoPanel(landscape);
                  return Column(
                    children: [
                      _header(),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                          child: landscape
                              ? Row(
                                  children: [
                                    Expanded(flex: 5, child: preview),
                                    const SizedBox(width: 24),
                                    Expanded(flex: 4, child: info),
                                  ],
                                )
                              : Column(
                                  children: [
                                    Expanded(child: preview),
                                    const SizedBox(height: 16),
                                    info,
                                  ],
                                ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            // Positioned must be the Stack's direct child; AnimatedSwitcher wraps its child in transitions.
            Positioned.fill(
              child: IgnorePointer(
                ignoring: _decision == null,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: _decision == null
                      ? const SizedBox.shrink()
                      : _ResultOverlay(key: ValueKey(_decision), decision: _decision!),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          child: const BrandLogo(height: 26),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _settings.terminalName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
              ),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _state.ready
                          ? Brand.granted
                          : (_state.initState == 'initializing' ? Brand.warning : Brand.denied),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      _state.statusLabel,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white60, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const _Clock(),
        IconButton(
          tooltip: 'Admin (long-press)',
          onPressed: () => toast(context, 'Press and hold to open the admin panel'),
          icon: GestureDetector(
            onLongPress: _openAdmin,
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.admin_panel_settings_outlined, color: Colors.white38),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _previewCard() {
    final color = _palmIn ? Brand.granted : const Color(0xFF8FA8E8);
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Brand.surfaceDark,
          border: Border.all(color: color.withValues(alpha: .6), width: 2),
          borderRadius: BorderRadius.circular(28),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (!_covered) PalmPreview(showRgb: _settings.qrEnabled),
            if (!_state.ready) _offline(),
            if (_state.ready) ScanOverlay(color: color, active: true),
            if (_state.ready)
              Positioned(
                left: 0,
                right: 0,
                bottom: 18,
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: (_palmIn ? Brand.granted : Colors.black).withValues(alpha: .55),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Text(
                      _palmIn ? 'Hold still…' : 'Scanning',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _offline() => Container(
    color: Brand.surfaceDark.withValues(alpha: .92),
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(_state.initState == 'initializing' ? Icons.hourglass_top : Icons.usb_off, size: 56, color: Colors.white54),
        const SizedBox(height: 16),
        Text(
          _state.statusLabel,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
        ),
        if (_state.initMessage != null || _state.initState == 'no_device') ...[
          const SizedBox(height: 8),
          Text(
            _state.initState == 'no_device'
                // Built-in scanners share the USB port: a PC/data cable switches it off.
                ? 'If a USB cable to a computer is plugged in, unplug it — the built-in scanner shares that port. '
                      'The scanner reconnects automatically.'
                : _state.initMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54),
          ),
        ],
        if (_state.initState != 'initializing') ...[
          const SizedBox(height: 20),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white30),
            ),
            onPressed: () => PalmBridge.instance.reinit(),
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ],
    ),
  );

  Widget _infoPanel(bool landscape) {
    final attendance = _settings.mode == TerminalMode.attendance;
    return Column(
      mainAxisSize: landscape ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.back_hand_outlined, color: Color(0xFF8FA8E8), size: 40),
        const SizedBox(height: 10),
        Text(
          attendance ? 'Scan your palm to check in or out' : 'Place your palm over the scanner',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          _settings.qrEnabled
              ? 'Hold your open hand 5–10 cm above the sensor, or show your QR pass'
              : 'Hold your open hand flat, 5–10 cm above the sensor',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white60, fontSize: 15),
        ),
        if (attendance) ...[
          const SizedBox(height: 18),
          SegmentedButton<String>(
            style: SegmentedButton.styleFrom(
              foregroundColor: Colors.white70,
              selectedForegroundColor: Colors.white,
              selectedBackgroundColor: Brand.blue,
              side: const BorderSide(color: Colors.white24),
            ),
            segments: const [
              ButtonSegment(value: 'auto', label: Text('Auto'), icon: Icon(Icons.autorenew)),
              ButtonSegment(value: 'in', label: Text('Check in'), icon: Icon(Icons.login)),
              ButtonSegment(value: 'out', label: Text('Check out'), icon: Icon(Icons.logout)),
            ],
            selected: {AccessEngine.instance.directionChoice},
            onSelectionChanged: (v) => setState(() => AccessEngine.instance.directionChoice = v.first),
          ),
        ],
      ],
    );
  }
}

class _Clock extends StatefulWidget {
  const _Clock();
  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> {
  late Timer _t;
  DateTime _now = DateTime.now();
  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) => setState(() => _now = DateTime.now()));
  }

  @override
  void dispose() {
    _t.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Text(
        DateFormat('HH:mm').format(_now),
        style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700, height: 1),
      ),
      Text(DateFormat('EEE, d MMM').format(_now), style: const TextStyle(color: Colors.white60, fontSize: 12)),
    ],
  );
}

class _ResultOverlay extends StatelessWidget {
  final AccessDecision decision;
  const _ResultOverlay({super.key, required this.decision});

  @override
  Widget build(BuildContext context) {
    final s = AppSettings.instance;
    final d = decision;
    final color = d.granted ? Brand.granted : Brand.denied;
    final user = d.user;
    final displayName = user == null ? null : (s.privacyNames ? user.name.split(' ').first : user.name);
    final title = d.granted
        ? (d.direction == 'out' ? 'Goodbye' : (d.direction == 'in' ? 'Checked in' : s.welcomeText))
        : 'Access denied';
    return SizedBox.expand(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color, Color.lerp(color, Colors.black, .35)!],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(d.granted ? Icons.check_circle_rounded : Icons.cancel_rounded, color: Colors.white, size: 88),
                  const SizedBox(height: 18),
                  Text(
                    title,
                    style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800),
                  ),
                  if (user != null) ...[
                    const SizedBox(height: 24),
                    if (s.showPhoto)
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                        child: UserAvatar(user: user, radius: 64),
                      ),
                    const SizedBox(height: 16),
                    Text(
                      displayName!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w700),
                    ),
                    if (!s.privacyNames && (user.departmentName ?? '').isNotEmpty)
                      Text(user.departmentName!, style: const TextStyle(color: Colors.white70, fontSize: 18)),
                  ],
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .18),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Text(
                      [
                        d.granted ? DateFormat('HH:mm:ss').format(d.at) : Reason.label(d.reason),
                        if (d.duplicate) 'already recorded',
                        if (s.showScore && d.score != null) 'score ${d.score}',
                      ].join(' · '),
                      style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
