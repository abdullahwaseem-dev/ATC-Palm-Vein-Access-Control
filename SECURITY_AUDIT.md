# ATC Palm Access: Security Audit

**App:** ATC Palm Access 1.0.0 (`com.atc.palmaccess`), Flutter + Kotlin, for HFSecurity VP530 palm-vein terminals
**Vendor SDK reviewed:** `vp530-android-sdk` v2.2.11 (Rockchip) / v2.2.12 (MTK), plus the vendor demo app `vp530Demo-20260928`
**Date:** 16 Nov 2026 (updated after on-device testing on an FP08 / MT8768 terminal)
**Method:** source review of the new app; bytecode inspection (`javap`) of the vendor AAR; inspection of the built release APK (`aapt2`, `apksigner`, `apkanalyzer`); automated tests.

---

## 1. Summary

| Area | Result |
|---|---|
| New app code | 5 issues found during the audit, **all fixed** before release (section 4) |
| Vendor demo app | 7 weaknesses, **all avoided** in the new app (section 3) |
| Vendor SDK (closed source) | 4 risks that **cannot be fixed in the app**; mitigated where possible (section 2) |
| Release APK | Signed with a new private RSA-4096 key, R8-minified, Dart obfuscated, no debug flags, no storage permissions, no cloud backup |

**Overall:** the app is suitable for production use as an offline access/attendance terminal. The main remaining risk comes from the vendor SDK's licence channel (plain HTTP). It only matters when the device is on an untrusted network. Recommendation R-1 (put the terminal on an isolated network or VLAN) addresses it.

Severity scale: **High** = exploitable remotely or defeats access control; **Medium** = needs network position or physical access plus skill; **Low** = defence in depth.

---

## 2. Vendor SDK findings (cannot be changed by us)

| ID | Severity | Finding | Evidence | Mitigation in this app |
|---|---|---|---|---|
| V-1 | Medium | Licence activation uses **plain HTTP** to `http://admin.hfims.com/app-api/internal/palm-license/get` and `http://123.60.25.75:9001/common/license/v1/checkLicense`. A network attacker could read or alter licence traffic (device key, machine code). | URL strings in `classes.jar`; `PalmAuthUtils` → `OkHttpTinyUtils.get()` | App-wide cleartext is **blocked** by `network_security_config.xml`; HTTP is allowed **only** for these two hosts. No biometric data goes over this channel. See R-1. |
| V-2 | Medium | The SDK's HTTP helper disables TLS hostname checks: `OkHttpTinyUtils.a(String, SSLSession)` always returns `true`, and it builds its own `TrustManager[]`. | `javap -c`: method body is `iconst_1; ireturn` | The SDK only calls the HTTP endpoints above. The app's own traffic (webhooks) uses the platform TLS stack with **system CAs only**. |
| V-3 | Low | A hard-coded key (`hfims1234567palm`) and app credentials are embedded in the SDK for licence storage and signing. | String constants in `PalmLicenseUtils` / `PalmAuthUtils` | None possible. The licence is device-bound. Ask the vendor for a fix (R-5). |
| V-4 | Low | The SDK keeps its own copy of palm templates in a greenDAO SQLite DB. Whether that DB is encrypted is undocumented. | `impl/db/PalmprintDao` | The SDK DB is placed in **app-private internal storage** (the demo used external storage). Android file-based encryption protects it at rest. |
| V-6 | Info | The Rockchip SDK builds (v2.2.11) do not expose the LED controller or calibration APIs. | `javap` of the r3xxx/r356x `classes.jar` | Those features are compiled per chipset; Rockchip builds use a no-op implementation and hide the controls. No security impact. |
| V-7 | Medium | **FP08 board (Hibory):** `/dev/hby_usbsw` and `/dev/mtgpio` are world-writable (`crwxrwxrwx`), so *any* installed app can toggle board GPIOs, cut power to the palm scanner or switch the USB controller. Found during on-device testing. | `ls -lZ /dev/hby_usbsw /dev/mtgpio` on FP08 firmware v1.0.1-20260807 | Deploy terminals as dedicated devices (home-app + kiosk mode, no other apps installed, Play Store disabled). Ask the board vendor to restrict these nodes to a system group. |
| V-5 | Info | The SDK includes an optional vendor cloud matching service (`serverHost`, default `47.245.112.242:8530`). | Demo `AppSettings` | **Disabled**: `serverHost("")` is hard-coded. Templates never leave the device. |

---

## 3. Vendor demo app weaknesses (not carried over)

| ID | Demo behaviour | New app |
|---|---|---|
| D-1 | Release signing key committed with password `111111` (`app/dt.jks`) | New RSA-4096 key, random password in an untracked `android/key.properties`; `*.jks` and `key.properties` are git-ignored |
| D-2 | Palm DB and app dir on **external storage** (`getExternalFilesDir`) | Internal app-private storage only. `READ/WRITE_EXTERNAL_STORAGE` removed from the merged manifest |
| D-3 | `android:allowBackup="true"` | `allowBackup=false` and `data_extraction_rules` exclude everything from cloud backup and device transfer |
| D-4 | `usesCleartextTraffic="true"` app-wide | Cleartext off. Allowed only for the two vendor licence hosts (V-1) |
| D-5 | No admin authentication: anyone at the device can add or delete users and wipe data | Admin PIN (PBKDF2 + hardware-key pepper), escalating lockout, auto-lock, optional admin-palm unlock, audit trail |
| D-6 | Palm templates handled only inside the SDK; no backup or recovery path | Templates encrypted with an Android Keystore AES-256-GCM key; encrypted, password-protected backups |
| D-7 | Old dependencies (OkHttp 3.11, Gson 2.8.2, greenDAO 3.2.2) | Latest API-compatible: OkHttp 3.14.9, Gson 2.11.0, greenDAO 3.3.0. fastjson (critical CVE history) **not included**: verified unused on the licence path |

---

## 4. Issues found in our own code during the audit (all fixed)

| ID | Severity | Issue | Fix |
|---|---|---|---|
| A-1 | Medium | An administrator whose account had **expired** (valid-until date passed) could still unlock the admin panel by palm | Admin palm login now checks status, role **and** the validity window (`admin_login.dart`) |
| A-2 | Medium | Duplicate-scan suppression also suppressed the webhook, so a door controller would not re-open for someone scanning twice within the window | Repeat scans still trigger the webhook (flagged `"duplicate": true`); only the log entry is de-duplicated (`services.dart`) |
| A-3 | Low | Session timeout could be paused indefinitely if an admin left the enrollment or calibration screen open | Paused timeout is now capped at 10 minutes (`auth.dart`) |
| A-4 | Low | Webhook signing secret stored in plaintext in SQLite | Stored as an Android Keystore-encrypted token; decrypted only when signing |
| A-5 | Low | Webhook errors were printed with `debugPrint` in release builds | Logging only in debug builds. `Log.d/i/v` stripped from release by R8 |

A sixth defect (a crash risk, not a security issue) was found by the automated screen tests: the user editor could build its dropdowns before reference data loaded. Fixed.

---

## 5. Security controls implemented

**Biometric data**
- Palm templates are encrypted at rest with **AES-256-GCM**, using a non-exportable **Android Keystore** key (hardware-backed where the device supports it).
- Templates exist in plaintext only in memory while being registered with the SDK.
- Vendor cloud matching is disabled; all matching is on-device.
- Templates are excluded from Android cloud backup and device-to-device transfer.

**Admin access**
- 6–8 digit PIN. Weak PINs (`000000`, `123456`, `654321`, …) are rejected.
- Stored as `PBKDF2-HMAC-SHA256(HMAC(Keystore pepper, PIN), salt, 120,000 iterations)`. A stolen database cannot be brute-forced offline because the pepper key never leaves the Keystore.
- Constant-time comparison (`MessageDigest.isEqual`).
- Escalating lockout after N failed attempts (default 5): 30 s, doubling, capped at 15 min. Persisted across restarts.
- Auto-lock after inactivity (default 3 min). The login screen itself times out after 60 s.
- Optional palm unlock for active, in-validity users with the Administrator role.
- `FLAG_SECURE`: no screenshots, screen recording or recent-apps thumbnails of personal data.

**Access decisions**
- Each grant checks account status, valid-from/until dates and weekly schedules (including overnight windows). Administrators bypass schedules only.
- Unknown templates found in the SDK library are deleted automatically.
- SDK match threshold is admin-configurable (55–90, default 65). The native layer clamps it to 40–95.
- The optional QR fallback is **off by default**, uses 96-bit random codes, and the UI labels it as weaker than palm.

**Auditability**
- Every admin action is recorded with actor, time and details: login, failed login, user CRUD, palm enroll/remove, settings changes (secrets masked), exports, backup/restore, calibration, retention purges.
- Access log retention is configurable (30 days to forever). The audit trail is kept for 2 years.

**Data export and integration**
- Backups: AES-256-GCM, key from PBKDF2-SHA256 (210,000 iterations) of an admin-chosen password (minimum 10 characters, letters and digits), with authenticated header data. The restore path bounds the iteration count to block resource-exhaustion files.
- Files are written only through the Android system file picker. No silent writes to shared storage.
- CSV exports neutralise spreadsheet formula injection (`=`, `+`, `-`, `@`).
- Webhooks: HTTPS only (enforced in the UI and by the network config), optional **HMAC-SHA256** signature over `timestamp.body` in `X-ATC-Signature` with `X-ATC-Timestamp`, 6 s timeout, one retry.

**Platform hardening**
- All SQL is parameterised.
- Exported components: launcher activity, the optional home-screen alias (disabled until an admin enables it), the boot receiver (checks for the system-protected `BOOT_COMPLETED` action), and AndroidX's profile receiver (requires the `DUMP` permission).
- The SDK's licence service runs in an isolated, non-exported process (`:enc_service`).
- Release builds: R8 shrinking, Dart `--obfuscate` with split debug info, no `debuggable` flag.
- Optional kiosk lock (screen pinning) and dedicated-device (home app) mode keep users inside the app.

---

## 6. Residual risks and recommendations

| ID | Priority | Recommendation |
|---|---|---|
| R-1 | High | Put terminals on an **isolated network or VLAN** with outbound access limited to the vendor licence hosts (and your webhook receiver). This neutralises V-1 and V-2. After the licence is activated, the scanner works fully offline. |
| R-2 | High | **Back up `android/atc-release.jks` and `android/key.properties`** to a secure offline location such as a password manager or safe. Without them you cannot publish updates that install over existing devices. |
| R-3 | Medium | Store backup files and their passwords separately. Treat backup files as biometric data under your privacy policy. |
| R-4 | Medium | If you use webhooks to open doors, the receiver **must** verify `X-ATC-Signature` and reject timestamps older than about 60 s (replay protection). |
| R-5 | Medium | Ask HFSecurity for an SDK build that uses HTTPS with certificate validation for licensing (V-1, V-2, V-3). |
| R-6 | Low | Non-biometric records (names, logs) sit in app-private SQLite protected by Android file-based encryption, not by an app-level key. If terminals may be stolen and rooted, consider SQLCipher in a future version. |
| R-7 | Low | Physically secure the terminal's USB and debug ports. Disable *Developer options / USB debugging* on deployed devices. |
| R-8 | Info | Biometric data is regulated in many jurisdictions (e.g. GDPR Art. 9, BIPA). Get written employee consent, publish a retention policy, and use the in-app retention setting. |

---

## 7. Verification evidence

- `flutter analyze`: no issues.
- `flutter test`: 4/4 passed (PIN policy, schedule windows including overnight, webhook HTTPS rule, full screen render with seeded database).
- Release APK (`app-mtk-release.apk`):
  - `apksigner verify`: OK, signer `CN=ATC Palm Access, O=ATC`.
  - `aapt2 dump permissions`: INTERNET, ACCESS_NETWORK_STATE, ACCESS_WIFI_STATE (from SDK), CAMERA, RECEIVE_BOOT_COMPLETED, VIBRATE. **No storage permissions.**
  - Manifest: `allowBackup=false`, `usesCleartextTraffic=false`, `networkSecurityConfig` set, `targetSdk 36`.
  - `apkanalyzer`: the SDK classes the vendor library loads by reflection (`PalmSdk`, `XinranSdkImpl`, `PalmprintDao`, `HscEncService`, `USBMonitor`, `UVCCamera`, greenDAO) are present after R8.

---

© 2026 ATC. All rights reserved. Confidential: see [LICENSE](LICENSE).
