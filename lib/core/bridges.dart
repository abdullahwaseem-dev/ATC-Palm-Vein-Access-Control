// Copyright (c) 2026 ATC. All rights reserved.
// Proprietary and confidential. Use, copying, modification or distribution without
// written permission from ATC is prohibited. See LICENSE in the repository root.

import 'dart:async';

import 'package:flutter/services.dart';

/// SDK result codes (from com.hfims.android.lib.palm.PalmConst).
class PalmCodes {
  static const collectPalmExists = 1;
  static const collectNotEnoughTimes = 2;
  static const collectUnknownError = 3;
  static const collectDbSaveError = 4;
  static const collectTimeout = 5;

  static const identifySuccess = 1;
  static const identifyLowScore = 2;
  static const identifyTimeout = 3;

  static const handUnknown = 0;
  static const handLeft = 1;
  static const handRight = 2;

  /// Human-readable guidance for enrollment failures.
  static String collectMessage(int result, int? errorCode) {
    if (result == collectPalmExists) return 'This palm is already registered to someone.';
    if (result == collectTimeout) return 'Timed out. Present your palm again.';
    if (result == collectDbSaveError) return 'Could not save the palm template.';
    if (result == collectNotEnoughTimes) return 'Not enough good captures. Try again.';
    return switch (errorCode) {
      359 => 'Palm not fully visible — open your hand and centre it.',
      354 || 358 => 'Too far — move your palm closer (5–10 cm).',
      352 => 'Too dark — move your palm closer to the sensor.',
      353 => 'Too bright — move your palm slightly away.',
      355 => 'Hold your palm flat and parallel to the scanner.',
      _ => 'Capture failed. Keep your palm steady and try again.',
    };
  }
}

/// Typed event from the native palm engine.
class PalmEvent {
  final String type; // init | camera | collect | recognize | calibration | qr
  final Map<String, dynamic> data;
  PalmEvent(this.type, this.data);
  String? get event => data['event'] as String?;
}

/// Wrapper around the VP530 SDK bridge (MainActivity "atc/palm").
class PalmBridge {
  PalmBridge._();
  static final instance = PalmBridge._();

  static const _ch = MethodChannel('atc/palm');
  static const _ev = EventChannel('atc/palm/events');

  Stream<PalmEvent>? _events;
  Stream<PalmEvent> get events => _events ??= _ev.receiveBroadcastStream().map((e) {
    final m = Map<String, dynamic>.from(e as Map);
    return PalmEvent(m['type'] as String, m);
  }).asBroadcastStream();

  Future<void> configure({
    required int threshold,
    required int irVid,
    required int irPid,
    required int rgbVid,
    required int rgbPid,
    required int rotation,
    required bool mirrorH,
    required bool mirrorV,
    required bool qrEnabled,
  }) => _ch.invokeMethod('configure', {
    'threshold': threshold,
    'irVid': irVid,
    'irPid': irPid,
    'rgbVid': rgbVid,
    'rgbPid': rgbPid,
    'rotation': rotation,
    'mirrorH': mirrorH,
    'mirrorV': mirrorV,
    'qrEnabled': qrEnabled,
  });

  Future<void> reinit() => _ch.invokeMethod('reinit');
  Future<Map<String, dynamic>> status() async => Map<String, dynamic>.from(await _ch.invokeMethod('status') as Map);
  Future<void> startRecognize() => _ch.invokeMethod('startRecognize');
  Future<void> stopRecognize() => _ch.invokeMethod('stopRecognize');
  Future<void> startCollect(String palmId) => _ch.invokeMethod('startCollect', {'palmId': palmId});
  Future<void> stopCollect() => _ch.invokeMethod('stopCollect');
  Future<int> maxCollectCount() async => (await _ch.invokeMethod<int>('maxCollectCount')) ?? 0;
  Future<void> led(String color) => _ch.invokeMethod('led', {'color': color});
  Future<void> pauseQr(int ms) => _ch.invokeMethod('pauseQr', {'ms': ms});

  Future<(bool, String?)> addFeature(String palmId, String feature) async {
    final r = Map<String, dynamic>.from(
      await _ch.invokeMethod('addFeature', {'palmId': palmId, 'feature': feature}) as Map,
    );
    return (r['ok'] == true, r['message'] as String?);
  }

  Future<bool> deleteFeature(String palmId) async =>
      (await _ch.invokeMethod<bool>('deleteFeature', {'palmId': palmId})) ?? false;
  Future<void> deleteAllFeatures() => _ch.invokeMethod('deleteAllFeatures');
  Future<int> featureCount() async => (await _ch.invokeMethod<int>('featureCount')) ?? -1;

  Future<(List<int>, String)> calibrationSample(int step, {int count = 20, int interval = 100}) async {
    final r = Map<String, dynamic>.from(
      await _ch.invokeMethod('calibrationSample', {'step': step, 'count': count, 'interval': interval}) as Map,
    );
    return ((r['values'] as List).cast<int>(), r['verdict'] as String);
  }

  Future<String> calibrate(List<int> nothing, List<int> near, List<int> far) async =>
      (await _ch.invokeMethod<String>('calibrate', {'nothing': nothing, 'near': near, 'far': far}))!;

  Future<List<Map<String, dynamic>>> usbDevices() async =>
      ((await _ch.invokeMethod('usbDevices')) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
}

/// Device-level services: Keystore crypto, kiosk mode, tones (MainActivity "atc/device").
class DeviceBridge {
  DeviceBridge._();
  static final instance = DeviceBridge._();
  static const _ch = MethodChannel('atc/device');

  Future<String> encrypt(String plain) async => (await _ch.invokeMethod<String>('encrypt', {'plain': plain}))!;
  Future<String> decrypt(String token) async => (await _ch.invokeMethod<String>('decrypt', {'token': token}))!;
  Future<String> hashPin(String pin) async => (await _ch.invokeMethod<String>('hashPin', {'pin': pin}))!;
  Future<bool> verifyPin(String pin, String hash) async =>
      (await _ch.invokeMethod<bool>('verifyPin', {'pin': pin, 'hash': hash})) ?? false;
  Future<String> encryptBackup(String plain, String password) async =>
      (await _ch.invokeMethod<String>('encryptBackup', {'plain': plain, 'password': password}))!;
  Future<String> decryptBackup({
    required String salt,
    required String iv,
    required String data,
    required int iterations,
    required String password,
  }) async => (await _ch.invokeMethod<String>('decryptBackup', {
    'salt': salt,
    'iv': iv,
    'data': data,
    'iterations': iterations,
    'password': password,
  }))!;
  Future<String> randomToken([int bytes = 32]) async =>
      (await _ch.invokeMethod<String>('randomToken', {'bytes': bytes}))!;
  Future<String> hmac(String key, String message) async =>
      (await _ch.invokeMethod<String>('hmac', {'key': key, 'message': message}))!;

  Future<bool> startKiosk() async => (await _ch.invokeMethod<bool>('startKiosk')) ?? false;
  Future<bool> stopKiosk() async => (await _ch.invokeMethod<bool>('stopKiosk')) ?? false;
  Future<bool> isKiosk() async => (await _ch.invokeMethod<bool>('isKiosk')) ?? false;
  Future<void> setLauncherMode(bool enabled) => _ch.invokeMethod('setLauncherMode', {'enabled': enabled});
  Future<bool> isLauncherMode() async => (await _ch.invokeMethod<bool>('isLauncherMode')) ?? false;
  Future<void> openHomeSettings() => _ch.invokeMethod('openHomeSettings');
  Future<void> setBootStart(bool enabled) => _ch.invokeMethod('setBootStart', {'enabled': enabled});
  Future<void> tone(String kind) => _ch.invokeMethod('tone', {'kind': kind});
  Future<Map<String, dynamic>> deviceInfo() async =>
      Map<String, dynamic>.from(await _ch.invokeMethod('deviceInfo') as Map);
}
