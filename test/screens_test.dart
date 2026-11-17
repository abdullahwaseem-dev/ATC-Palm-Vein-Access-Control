// Copyright (c) 2026 ATC. All rights reserved.
// Proprietary and confidential. Use, copying, modification or distribution without
// written permission from ATC is prohibited. See LICENSE in the repository root.

// Visual + logic smoke tests. Native channels are mocked; SQLite runs via FFI.
// Regenerate screenshots: flutter test --update-goldens test/screens_test.dart
import 'dart:io';

import 'package:atc_palm_access/core/app_state.dart';
import 'package:atc_palm_access/core/auth.dart';
import 'package:atc_palm_access/core/db.dart';
import 'package:atc_palm_access/core/models.dart';
import 'package:atc_palm_access/core/services.dart';
import 'package:atc_palm_access/core/settings.dart';
import 'package:atc_palm_access/screens/admin/admin_shell.dart';
import 'package:atc_palm_access/screens/admin/user_edit_page.dart';
import 'package:atc_palm_access/screens/admin_login.dart';
import 'package:atc_palm_access/screens/kiosk_screen.dart';
import 'package:atc_palm_access/screens/setup_wizard.dart';
import 'package:atc_palm_access/widgets/common.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Real fonts for readable screenshots; `flutter test` sets FLUTTER_ROOT.
final _fontDir = [
  Platform.environment['FLUTTER_ROOT'] ?? '',
  'bin',
  'cache',
  'artifacts',
  'material_fonts',
].join(Platform.pathSeparator);

Future<void> _loadFonts() async {
  final roboto = FontLoader('Roboto');
  for (final f in ['roboto-regular.ttf', 'roboto-medium.ttf', 'roboto-bold.ttf', 'roboto-black.ttf']) {
    final file = File('$_fontDir${Platform.pathSeparator}$f');
    if (file.existsSync()) roboto.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
  }
  await roboto.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(File('$_fontDir${Platform.pathSeparator}materialicons-regular.otf').readAsBytesSync())));
  await icons.load();
}

MockStreamHandlerEventSink? _eventSink;

void _mockChannels() {
  final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  m.setMockMethodCallHandler(
    const MethodChannel('atc/palm'),
    (call) async => switch (call.method) {
      'status' => {
        'initState': 'ready',
        'irAttached': true,
        'rgbAttached': false,
        'featureCount': 3,
        'platform': 'MTK',
      },
      'featureCount' => 3,
      'addFeature' => {'ok': true},
      'usbDevices' => <Object>[],
      _ => null,
    },
  );
  m.setMockMethodCallHandler(const MethodChannel('atc/device'), (call) async {
    final a = (call.arguments as Map?) ?? {};
    return switch (call.method) {
      'hashPin' => 'pbkdf2\$1\$c2FsdA==\$${a['pin']}',
      'verifyPin' => (a['hash'] as String).endsWith('\$${a['pin']}'),
      'encrypt' => 'v1:iv:${a['plain']}',
      'decrypt' => (a['token'] as String).split(':').last,
      'randomToken' => 'abc123XYZ',
      'deviceInfo' => {'model': 'VP530', 'manufacturer': 'HF', 'android': '11', 'appVersion': '1.0.0', 'build': 1},
      'isLauncherMode' || 'isKiosk' => false,
      _ => null,
    };
  });
  m.setMockStreamHandler(
    const EventChannel('atc/palm/events'),
    MockStreamHandler.inline(
      onListen: (_, sink) {
        _eventSink = sink;
        sink.success({'type': 'init', 'state': 'ready'});
      },
    ),
  );
  m.setMockMethodCallHandler(const MethodChannel('flutter_tts'), (_) async => 1);
}

Future<void> _seed() async {
  final db = AppDb.instance;
  await AppSettings.instance.setMany({
    'setup_done': true,
    'admin_pin_hash': 'pbkdf2\$1\$c2FsdA==\$482916',
    'mode': 'attendance',
  });
  final eng = await db.saveDepartment(Department(name: 'Engineering'));
  final ops = await db.saveDepartment(Department(name: 'Operations'));
  final people = [
    ('Amina Yusuf', 'E1001', eng, UserRole.admin, true, true),
    ('Daniel Okoro', 'E1002', eng, UserRole.employee, true, false),
    ('Sara Malik', 'E1003', ops, UserRole.employee, false, true),
    ('James Carter', 'V2001', ops, UserRole.visitor, false, false),
  ];
  for (final (name, code, dept, role, l, r) in people) {
    await db.saveUser(
      AppUser(
        code: code,
        name: name,
        departmentId: dept,
        role: role,
        scheduleId: 1,
        leftPalmId: l ? 'L_$code' : null,
        leftFeature: l ? 'v1:iv:feat' : null,
        rightPalmId: r ? 'R_$code' : null,
        rightFeature: r ? 'v1:iv:feat' : null,
      ),
    );
  }
  final now = DateTime.now();
  var i = 0;
  for (var d = 6; d >= 0; d--) {
    for (var k = 0; k < 4 + (d % 3) * 2; k++) {
      final ts = DateTime(now.year, now.month, now.day - d, 8 + (k % 9), (k * 7) % 60);
      if (ts.isAfter(now)) continue;
      final ok = k % 5 != 4;
      final u = people[i++ % people.length];
      await db.insertLog(
        AccessLog(
          ts: ts,
          userId: ok ? (i % 4) + 1 : null,
          userName: ok ? u.$1 : null,
          userCode: ok ? u.$2 : null,
          method: 'palmRight',
          granted: ok,
          reason: ok ? Reason.granted : Reason.unknown,
          score: ok ? 80 + k : 41,
          direction: ok ? (k.isEven ? 'in' : 'out') : '',
        ),
      );
    }
  }
}

ThemeData _testTheme() {
  final t = buildTheme(Brightness.light);
  return t.copyWith(
    textTheme: t.textTheme.apply(fontFamily: 'Roboto'),
    primaryTextTheme: t.primaryTextTheme.apply(fontFamily: 'Roboto'),
  );
}

Widget _app(Widget home) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: _testTheme(),
  navigatorObservers: [routeObserver],
  home: home,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    _mockChannels();
    await _loadFonts();
  });

  group('logic', () {
    test('PIN policy rejects weak PINs', () {
      expect(AuthService.isValidPin('123456'), isFalse);
      expect(AuthService.isValidPin('000000'), isFalse);
      expect(AuthService.isValidPin('654321'), isFalse);
      expect(AuthService.isValidPin('12345'), isFalse);
      expect(AuthService.isValidPin('48291a'), isFalse);
      expect(AuthService.isValidPin('482916'), isTrue);
    });

    test('schedule windows incl. overnight shifts', () {
      final office = AccessSchedule(name: 'o', days: 0x1F, startMinute: 8 * 60, endMinute: 17 * 60);
      expect(office.allows(DateTime(2026, 11, 16, 9)), isTrue); // Monday
      expect(office.allows(DateTime(2026, 11, 16, 18)), isFalse);
      expect(office.allows(DateTime(2026, 11, 15, 9)), isFalse); // Sunday
      final night = AccessSchedule(name: 'n', startMinute: 22 * 60, endMinute: 6 * 60);
      expect(night.allows(DateTime(2026, 11, 16, 23)), isTrue);
      expect(night.allows(DateTime(2026, 11, 16, 3)), isTrue);
      expect(night.allows(DateTime(2026, 11, 16, 12)), isFalse);
    });

    test('webhook URL must be https', () {
      expect(WebhookService.validateUrl('http://door.local/open'), isNotNull);
      expect(WebhookService.validateUrl('https://erp.example.com/hook'), isNull);
      expect(WebhookService.validateUrl(''), isNull);
    });
  });

  testWidgets('screens render', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows; // platform view shows placeholder in tests
    tester.view.physicalSize = const Size(800, 1280);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      final path = '${await getDatabasesPath()}${Platform.pathSeparator}atc_palm_access.db';
      if (File(path).existsSync()) File(path).deleteSync();
      await AppDb.instance.open();
      await AppSettings.instance.load();
      await _seed();
      await AppState.instance.start();
    });

    Future<void> shot(Widget w, String name, {Future<void> Function()? before}) async {
      await tester.pumpWidget(_app(w));
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 400)));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      if (before != null) await before();
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
      await tester.pump(const Duration(milliseconds: 300));
      // Screens show live time/date, so screenshots are written for review (--update-goldens) rather than diffed.
      if (autoUpdateGoldenFiles) await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));
    }

    await shot(const SetupWizard(), 'setup_wizard');
    await tester.tap(find.text('Get started'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Continue'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Create admin PIN'), findsOneWidget);
    if (autoUpdateGoldenFiles) await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/setup_pin.png'));
    await shot(const KioskScreen(), 'kiosk');
    await shot(const AdminLoginScreen(), 'admin_login');

    // Regression: a recognised palm must render the result overlay without layout errors
    // (a misplaced Positioned rendered as a grey box in release builds).
    await tester.pumpWidget(_app(const KioskScreen()));
    await tester.pump(const Duration(milliseconds: 100));
    _eventSink!.success({'type': 'recognize', 'event': 'success', 'palmId': 'R_E1003', 'score': 91});
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 500)));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);
    expect(find.text('Sara Malik'), findsOneWidget);
    if (autoUpdateGoldenFiles) {
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/kiosk_result.png'));
    }
    await tester.pump(const Duration(seconds: 5)); // overlay times out and animates away
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);

    // Denied path in access mode: unknown palm (low score) shows the red overlay.
    await tester.runAsync(() => AppSettings.instance.set('mode', 'access'));
    await tester.pump(const Duration(seconds: 1));
    _eventSink!.success({'type': 'recognize', 'event': 'failure', 'result': 2, 'score': 30});
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 500)));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);
    expect(find.text('Access denied'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);

    // Result overlay as shown after a successful scan.
    await tester.runAsync(() => AccessEngine.instance.onPalm('R_E1003', 88));
    await tester.runAsync(() async => AuthService.instance.loginWithPalm('Amina Yusuf'));
    await shot(const AdminShell(), 'dashboard');
    final user = await tester.runAsync(() => AppDb.instance.userById(1));
    await shot(UserEditPage(user: user), 'user_edit');
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => AuthService.instance.logout());
    debugDefaultTargetPlatformOverride = null;
  });
}
