# Hardware Notes: VP530 Palm-Vein Module and FP08 Terminal

© 2026 ATC. All rights reserved.

## VP530 palm-vein module

| Item | Value |
|---|---|
| Interface | USB 2.0, UVC |
| IR (vein) camera | `0x1D6C:0x0103` (type A) or `0x0507:0x0581` (type B), 640×480 |
| RGB camera (optional, QR) | `0x2C7F:0x4A60`, 640×480 |
| Indicator | RGB LED controlled through the IR camera's vendor (XU) channel |
| SDK | HFSecurity VP530 Android SDK 2.2.x (`com.hfims.android.lib.palm`) |
| Recognition | On-device 1:N, configurable threshold (default 65), IR liveness model |

## FP08 terminal (MediaTek MT8768, Android 13)

The FP08 has a **single USB controller** (`musb-hdrc`, OTG) shared by:

- the external **USB-C port** (PC / ADB connection, device mode), and
- the **built-in VP530 scanner** (host mode).

A board driver switches between the two:

| Item | Detail |
|---|---|
| Kernel driver | `usbhost_switch` with GPIOs `host5v_en`, `usb_switch_ctrl`, `usbid_ctrl`, `otg_detect` |
| Device node | `/dev/hby_usbsw` (Hibory) |
| Native library | `libHibory_CommonApi.so`, JNI class `android.hibory.CommonApi` |
| Power-on sequence | `setGpioDir(28,1); setGpioOut(28,1)` (USB-host 5 V) · `setGpioDir(159,1); setGpioOut(159,1)` (module power) · `setUsbHost(1)` |
| Power-off | `setUsbHost(0)` |

**What this means in practice**

1. While a PC cable is connected, the controller stays in device mode and the scanner is unpowered.
2. ATC Palm Access performs the power-on sequence before every SDK initialisation (`PalmExtras.scannerPower`) and hands the port back when the app closes.
3. If the switch was used while a PC cable was attached, the controller can stay latched until a **full restart** (`setUsbHost` returns −1). Restart the terminal with no cable attached.
4. For development, use **Wireless debugging** (Developer options) instead of a USB cable.

## Chipset build flavors

| Flavor | SDK | Notes |
|---|---|---|
| `mtk` | VP530 SDK 2.2.12 (MTK, bundled UVC) | LED, calibration and FP08 power switch supported |
| `r3xxx` | VP530 SDK 2.2.11 (RK 3xxx) + eyecool UVC | No LED/calibration API; UI hides those controls |
| `r356x` | VP530 SDK 2.2.11 (RK 356x) + eyecool UVC | Android 9+, higher recognise-retry count |

Chipset-specific code lives in `android/app/src/mtk/` and `android/app/src/rk/` (`PalmExtras`).
