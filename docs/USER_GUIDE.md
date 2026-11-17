# ATC Palm Access: User Guide

© 2026 ATC. All rights reserved. For authorised ATC customers and staff.

## 1. Installation

| Installer | Terminal chipset |
|---|---|
| `ATC-PalmAccess-<version>-mtk.apk` | MediaTek, e.g. **FP08 (MT8768)** |
| `ATC-PalmAccess-<version>-r3xxx.apk` | Rockchip RK3288 / RK3399 / RK33xx |
| `ATC-PalmAccess-<version>-r356x.apk` | Rockchip RK3566 / RK3568 |

1. Copy the matching APK to the terminal and open it, or run `adb install -r <file>.apk`.
2. Connect the terminal to the internet **once**. The palm scanner licence activates automatically on first start.
3. If Android asks for USB permission for the palm camera, tick **Use by default** and tap **OK**.

> **FP08 / built-in scanner:** the scanner shares the USB-C port. **Unplug any PC/USB cable** while using the app; the app powers the scanner itself. If the scanner was in use while a PC cable was connected, restart the terminal once. See [HARDWARE.md](HARDWARE.md).

## 2. First-run setup

1. **Terminal identity:** company name and door/terminal name.
2. **Admin PIN:** 6–8 digits; weak PINs (123456, 000000, …) are refused. Enter it twice.
3. **Mode:** *Access control* (door) or *Attendance* (check-in/out with working-hours reports).
4. **Scanner check:** shows whether the palm module is ready. You can finish setup and connect it later.

## 3. Daily use (terminal screen)

- Hold an **open, flat hand 5–10 cm above the sensor**, fingers slightly apart.
- **Green screen** + green LED + greeting = access granted / checked in.
- **Red screen** + red LED = denied, with the reason (not recognised, suspended, expired, outside hours).
- In *Attendance* mode choose **Auto / Check in / Check out** at the bottom of the screen.
- **Admin panel:** **press and hold** the shield icon (top right), then enter the PIN or scan an administrator's palm.

## 4. Enrolling people

1. Admin → **Users → Add user**.
2. Enter name and employee ID, plus optional photo, department, role, phone, email, schedule, validity dates and QR pass.
3. Under **Palm enrollment** tap **Enroll** for the left and/or right palm and follow the on-screen prompts until the ring completes.
4. Tips: clean, dry hand · keep it still · same distance each time · enroll **both hands** for reliability.

Roles: **Administrator** (can unlock the admin panel by palm and isn't limited by schedules), **Employee**, **Visitor**, **Contractor**.

## 5. Admin sections

| Section | Use it to |
|---|---|
| Dashboard | See users, today's granted/denied, who's present, charts, recent activity |
| Users | Add, edit, suspend, set expiry/schedule, enroll or remove palms, export CSV |
| Access log | Search and filter every scan; export CSV |
| Attendance | First-in / last-out / hours per person per day; export CSV |
| Departments & schedules | Manage departments and weekly time windows |
| Scanner & device | Check status, rebuild palm library, **calibrate sensor**, test LED, choose camera, rotation |
| Settings | Terminal, feedback, privacy, threshold, QR fallback, security, kiosk, webhook, retention, backup |
| Audit trail | See who did what and when |

## 6. Kiosk / dedicated-device setup

Settings → Security:
1. **Dedicated device (set as home app)** → choose ATC Palm Access as the default home app.
2. **Start on boot**.
3. **Kiosk lock (screen pinning)** keeps users from leaving the app.

## 7. Webhook integration

Settings → Integration → set an `https://` URL → **Generate** a signing secret → **Send test event**.

```json
{"event":"access","terminal":"Main Entrance","timestamp":"2026-11-16T08:01:12Z","granted":true,
 "reason":"granted","method":"palmRight","direction":"in","duplicate":false,"score":86,
 "user":{"code":"E1001","name":"Jane Doe","department":"Engineering","role":"employee"}}
```

Headers: `X-ATC-Timestamp` and `X-ATC-Signature: sha256=<hex HMAC-SHA256(secret, timestamp + "." + body)>`. The receiver must verify the signature and reject timestamps older than about 60 s.

## 8. Backup and moving to a new terminal

Settings → Data → **Create encrypted backup** → choose a strong password (10+ characters, letters and digits) → save the file.
On the new terminal: install, complete setup, then **Restore from backup**. Users, palm templates, schedules and logs are restored, and nobody needs to re-enroll. Store the file and the password separately.

## 9. Troubleshooting

| Symptom | Fix |
|---|---|
| "Palm module not connected" | Unplug any PC/USB cable from the terminal (FP08). If it persists, restart the terminal. Check Scanner & device → camera ID `0x1D6C:0x0103` |
| "Scanner licence not activated" | Connect to the internet and tap **Retry** |
| Palm often not recognised | Re-enroll, enroll both hands, run **Calibrate sensor**, or lower the match threshold slightly (default 65) |
| Image rotated or mirrored | Scanner & device → rotation / mirror switches |
| Forgot admin PIN | Use an Administrator's palm. Otherwise contact ATC support (factory reset erases data) |
