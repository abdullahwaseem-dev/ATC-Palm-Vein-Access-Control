# Architecture

© 2026 ATC. All rights reserved.

## Layers

| Layer | Location | Responsibility |
|---|---|---|
| UI | `lib/screens/`, `lib/widgets/` | Setup wizard, kiosk terminal, admin login, enrollment, calibration, admin pages |
| Domain | `lib/core/services.dart` | `AccessEngine` (rules, schedules, duplicates, logging, feedback), `PalmLibrary` (template lifecycle), `WebhookService` |
| Security | `lib/core/auth.dart`, `SecureVault.kt` | PIN policy and lockout, session timeout, Keystore crypto |
| Data | `lib/core/db.dart`, `models.dart`, `settings.dart` | SQLite schema, queries, reports, retention, settings |
| Backup | `lib/core/backup.dart` | Encrypted backup/restore, CSV exports with formula-injection protection |
| Bridge | `lib/core/bridges.dart` ↔ `MainActivity.kt` | `atc/palm` + `atc/device` method channels, `atc/palm/events` event channel |
| Native engine | `PalmEngine.kt` | VP530 SDK lifecycle, recognition, enrollment, library, calibration, QR |
| Camera | `UvcCamera.kt`, `PalmPreviewView.kt` | USB UVC capture, LED controller, rotated preview platform view |
| Chipset | `src/mtk|rk/.../PalmExtras.kt` | LED/calibration APIs, FP08 scanner power switch |

## Data model (SQLite, app-private)

| Table | Key columns |
|---|---|
| `users` | code (unique), name, department_id, role, status, valid_from/until, schedule_id, qr_code (unique), left/right_palm_id (unique), left/right_feature (**Keystore-encrypted**) |
| `departments` | name (unique) |
| `schedules` | days bitmask (Mon=bit0), start_min, end_min (overnight supported) |
| `access_logs` | ts, user snapshot, method, granted, reason, score, direction |
| `audit_logs` | ts, actor, action, details |
| `settings` | key/value |

## Recognition flow

```
UVC IR frame ─▶ PalmCamera(rotation, mirror, preview size) ─▶ PalmSdk.setDataSource
                                                                 │
PalmSdk RecognizeCallback ─▶ EventChannel {type:recognize, event:success, palmId, score}
                                                                 │
AccessEngine.onPalm ─▶ user lookup ─▶ status / validity / schedule ─▶ duplicate check
     ─▶ access_logs insert ─▶ webhook (HMAC) ─▶ LED + tone + TTS ─▶ result overlay ─▶ restart recognition
```

## Enrollment flow

`startCollect(palmId)` → SDK captures several frames → `success(feature)` → `addFeature(palmId, feature)` into the SDK library → feature encrypted with the Keystore (`v1:iv:ciphertext`) → stored on the user row → audit entry.
On startup, if the SDK library count differs from the database, the library is rebuilt from the encrypted templates.

## Native bridge API (`atc/palm`)

`configure`, `reinit`, `status`, `startRecognize`, `stopRecognize`, `startCollect`, `stopCollect`, `addFeature`, `deleteFeature`, `deleteAllFeatures`, `featureCount`, `led`, `pauseQr`, `calibrationSample`, `calibrate`, `usbDevices`.

Device API (`atc/device`): Keystore `encrypt`/`decrypt`, `hashPin`/`verifyPin`, `encryptBackup`/`decryptBackup`, `hmac`, `randomToken`, kiosk (`startKiosk`, `stopKiosk`, `setLauncherMode`, `setBootStart`), `tone`, `deviceInfo`.

## Building (authorised developers only)

Building requires the licensed vendor SDK binaries (see `android/app/libs/README.md`) and ATC's release keystore (`android/key.properties` + `android/atc-release.jks`), neither of which is in this repository.

```bash
flutter pub get
flutter analyze && flutter test
flutter build apk --release --flavor mtk --target-platform android-arm,android-arm64 \
  --obfuscate --split-debug-info=build/symbols/mtk
```

Notes: set `kotlin.incremental=false` in `android/gradle.properties` when the project and pub cache are on different drives (Windows). `-PqaScreenshots=true` produces an internal QA build that allows screenshots; never ship it.
