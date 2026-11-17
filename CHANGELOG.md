# Changelog

All notable changes to ATC Palm Access. © 2026 ATC. All rights reserved.

## [1.0.0] - 2026-11-16

### Added
- Palm-vein identification (1:N) for HFSecurity VP530 modules; left and right palm enrollment
- Kiosk terminal with live IR preview, result overlay, LED, beep and text-to-speech feedback
- Access rules: account status, validity dates, weekly schedules (including overnight), duplicate suppression
- Attendance mode with check-in/out and working-hours report
- Admin panel: dashboard and charts, users, access log, attendance, departments & schedules, scanner & device, settings, audit trail
- Admin authentication: Keystore-peppered PBKDF2 PIN, lockout, auto-lock, administrator palm unlock
- Encrypted backup/restore, CSV exports, signed HTTPS webhooks, data retention
- Kiosk/dedicated-device mode: screen pinning, home-app mode, start on boot
- Chipset builds: MediaTek (`mtk`), Rockchip 3xxx (`r3xxx`), Rockchip 356x (`r356x`)
- FP08 (MT8768) built-in scanner power control via the board USB switch
- Optional QR-code pass fallback via the RGB camera
- Security audit (see SECURITY_AUDIT.md)

### Fixed during on-device testing (FP08)
- Built-in scanner reported "not connected": the app now powers the scanner through the board switch
- App locked to portrait so the IR image is never rotated by auto-rotate
- Access result overlay rendered as a grey box in release builds (misplaced `Positioned`)
- Clearer "not connected" guidance when a PC cable occupies the shared USB port
