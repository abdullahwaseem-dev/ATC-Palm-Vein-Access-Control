// Copyright (c) 2026 ATC. All rights reserved.
// Proprietary and confidential. Use, copying, modification or distribution without
// written permission from ATC is prohibited. See LICENSE in the repository root.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../core/models.dart';

/// ATC brand palette (from the company logo).
class Brand {
  static const blue = Color(0xFF4262AC);
  static const blueDark = Color(0xFF2E4A8C);
  static const charcoal = Color(0xFF353535);
  static const ink = Color(0xFF0B1220);
  static const surfaceDark = Color(0xFF131C2E);
  static const granted = Color(0xFF16A34A);
  static const denied = Color(0xFFDC2626);
  static const warning = Color(0xFFD97706);
}

ThemeData buildTheme(Brightness b) {
  final scheme = ColorScheme.fromSeed(
    seedColor: Brand.blue,
    brightness: b,
    primary: b == Brightness.light ? Brand.blue : const Color(0xFF8FA8E8),
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: b);
  return base.copyWith(
    scaffoldBackgroundColor: b == Brightness.light ? const Color(0xFFF5F7FB) : Brand.ink,
    appBarTheme: AppBarTheme(
      backgroundColor: b == Brightness.light ? Colors.white : Brand.surfaceDark,
      foregroundColor: b == Brightness.light ? Brand.charcoal : Colors.white,
      elevation: 0,
      scrolledUnderElevation: 1,
      centerTitle: false,
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        color: b == Brightness.light ? Brand.charcoal : Colors.white,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: b == Brightness.light ? Colors.white : Brand.surfaceDark,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: b == Brightness.light ? const Color(0xFFE4E8F0) : Colors.white10),
      ),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: b == Brightness.light ? Colors.white : Colors.white10,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 16)),
  );
}

class BrandLogo extends StatelessWidget {
  final double height;
  final bool light;
  const BrandLogo({super.key, this.height = 36, this.light = false});
  @override
  Widget build(BuildContext context) =>
      Image.asset(light ? 'assets/brand/logo_light.png' : 'assets/brand/logo.png', height: height, fit: BoxFit.contain);
}

class BrandMark extends StatelessWidget {
  final double size;
  const BrandMark({super.key, this.size = 40});
  @override
  Widget build(BuildContext context) => Image.asset('assets/brand/mark.png', width: size, height: size);
}

/// Live VP530 IR preview hosted as an Android platform view (hybrid composition,
/// so the rotated TextureView renders exactly as on a native screen).
class PalmPreview extends StatelessWidget {
  final bool showRgb;
  const PalmPreview({super.key, this.showRgb = false});

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return const ColoredBox(
        color: Brand.ink,
        child: Center(
          child: Text('Preview available on device', style: TextStyle(color: Colors.white54)),
        ),
      );
    }
    const viewType = 'atc/palm_preview';
    final params = {'showRgb': showRgb};
    return PlatformViewLink(
      viewType: viewType,
      surfaceFactory: (context, controller) => AndroidViewSurface(
        controller: controller as AndroidViewController,
        gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
        hitTestBehavior: PlatformViewHitTestBehavior.transparent,
      ),
      onCreatePlatformView: (p) =>
          PlatformViewsService.initExpensiveAndroidView(
              id: p.id,
              viewType: viewType,
              layoutDirection: TextDirection.ltr,
              creationParams: params,
              creationParamsCodec: const StandardMessageCodec(),
              onFocus: () => p.onFocusChanged(true),
            )
            ..addOnPlatformViewCreatedListener(p.onPlatformViewCreated)
            ..create(),
    );
  }
}

/// Animated guide drawn over the preview: corner brackets + sweeping scan line.
class ScanOverlay extends StatefulWidget {
  final Color color;
  final bool active;
  const ScanOverlay({super.key, this.color = Brand.blue, this.active = true});
  @override
  State<ScanOverlay> createState() => _ScanOverlayState();
}

class _ScanOverlayState extends State<ScanOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))
    ..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedBuilder(
      animation: _c,
      builder: (_, _) => CustomPaint(painter: _ScanPainter(widget.color, widget.active ? _c.value : -1)),
    ),
  );
}

class _ScanPainter extends CustomPainter {
  final Color color;
  final double t;
  _ScanPainter(this.color, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final inset = size.shortestSide * 0.12;
    final r = Rect.fromLTRB(inset, inset, size.width - inset, size.height - inset);
    final len = size.shortestSide * 0.12;
    final p = Paint()
      ..color = color
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final (c, dx, dy) in [
      (r.topLeft, 1.0, 1.0),
      (r.topRight, -1.0, 1.0),
      (r.bottomLeft, 1.0, -1.0),
      (r.bottomRight, -1.0, -1.0),
    ]) {
      canvas.drawLine(c, c + Offset(len * dx, 0), p);
      canvas.drawLine(c, c + Offset(0, len * dy), p);
    }
    if (t >= 0) {
      final y = r.top + r.height * t;
      final g = Paint()
        ..shader = LinearGradient(
          colors: [color.withValues(alpha: 0), color.withValues(alpha: .9), color.withValues(alpha: 0)],
        ).createShader(Rect.fromLTWH(r.left, y - 2, r.width, 4));
      canvas.drawRect(Rect.fromLTWH(r.left, y - 1.5, r.width, 3), g);
    }
  }

  @override
  bool shouldRepaint(_ScanPainter old) => old.t != t || old.color != color;
}

class UserAvatar extends StatelessWidget {
  final AppUser? user;
  final double radius;
  const UserAvatar({super.key, this.user, this.radius = 22});
  @override
  Widget build(BuildContext context) {
    final photo = user?.photoPath;
    if (photo != null && File(photo).existsSync()) {
      return CircleAvatar(radius: radius, backgroundImage: FileImage(File(photo)));
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: Brand.blue.withValues(alpha: .15),
      child: Text(
        user?.initials ?? '?',
        style: TextStyle(color: Brand.blue, fontWeight: FontWeight.w700, fontSize: radius * .75),
      ),
    );
  }
}

/// Numeric PIN pad with obscured dots.
class PinPad extends StatefulWidget {
  final int maxLength;
  final ValueChanged<String> onSubmit;
  final bool dark;
  final bool enabled;
  const PinPad({super.key, required this.onSubmit, this.maxLength = 8, this.dark = false, this.enabled = true});
  @override
  State<PinPad> createState() => PinPadState();
}

class PinPadState extends State<PinPad> {
  String _pin = '';
  void clear() => setState(() => _pin = '');

  void _tap(String k) {
    if (!widget.enabled) return;
    HapticFeedback.selectionClick();
    setState(() {
      if (k == '<') {
        if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
      } else if (k == 'OK') {
        if (_pin.length >= 6) widget.onSubmit(_pin);
      } else if (_pin.length < widget.maxLength) {
        _pin += k;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final fg = widget.dark ? Colors.white : Brand.charcoal;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 28,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < (_pin.length < 6 ? 6 : _pin.length); i++)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < _pin.length ? Brand.blue : Colors.transparent,
                    border: Border.all(color: i < _pin.length ? Brand.blue : fg.withValues(alpha: .35), width: 2),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
          ['<', '0', 'OK'],
        ])
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final k in row)
                Padding(
                  padding: const EdgeInsets.all(6),
                  child: SizedBox(
                    width: 78,
                    height: 64,
                    child: Material(
                      color: k == 'OK'
                          ? (_pin.length >= 6 ? Brand.blue : Brand.blue.withValues(alpha: .35))
                          : (widget.dark ? Colors.white10 : Colors.white),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: widget.dark ? Colors.white12 : const Color(0xFFE4E8F0)),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => _tap(k),
                        child: Center(
                          child: k == '<'
                              ? Icon(Icons.backspace_outlined, color: fg)
                              : Text(
                                  k,
                                  style: TextStyle(
                                    fontSize: k == 'OK' ? 18 : 26,
                                    fontWeight: FontWeight.w600,
                                    color: k == 'OK' ? Colors.white : fg,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String text;
  const SectionHeader(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
    child: Text(
      text.toUpperCase(),
      style: Theme.of(
        context,
      ).textTheme.labelMedium?.copyWith(letterSpacing: 1.1, fontWeight: FontWeight.w700, color: Brand.blue),
    ),
  );
}

class StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  const StatusPill(this.label, this.color, {super.key, this.icon});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(20)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: 4)],
        Text(
          label,
          style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12),
        ),
      ],
    ),
  );
}

Future<bool> confirm(
  BuildContext context,
  String title,
  String message, {
  String ok = 'Confirm',
  bool destructive = false,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: Brand.denied) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r == true;
}

void toast(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? Brand.denied : null,
      ),
    );
}

/// Shared route observer so camera screens can release the preview when covered.
final routeObserver = RouteObserver<ModalRoute<void>>();
