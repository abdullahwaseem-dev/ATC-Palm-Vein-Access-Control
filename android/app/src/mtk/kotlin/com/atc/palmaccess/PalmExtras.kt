// Copyright (c) 2026 ATC. All rights reserved.
// Proprietary and confidential. Use, copying, modification or distribution without
// written permission from ATC is prohibited. See LICENSE in the repository root.

package com.atc.palmaccess

import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.util.Log
import com.hfims.android.lib.palm.PalmSdk

/** MTK SDK (v2.2.12): LED controller, distance calibration, and FP08 scanner power control. */
object PalmExtras {
    const val SUPPORTED = true
    private const val TAG = "PalmExtras"

    /**
     * GPIOs from the board maker's (Hibory) factory test tool: 28 = USB-host 5 V for the internal
     * port (HFUsb.openUsbHost); 159 = extra module power, used only on builds whose DISPLAY contains "USB".
     */
    private const val USB_HOST_GPIO = 28
    private const val MODULE_POWER_GPIO = 159

    private val commonApi: android.hibory.CommonApi? by lazy {
        // No File.exists() pre-check: SELinux may hide /dev entries from stat() even though open() is allowed.
        try { android.hibory.CommonApi() } catch (e: Throwable) { Log.w(TAG, "Hibory API unavailable", e); null }
    }

    /**
     * Powers the built-in scanner and switches the shared USB controller to host mode.
     * While on, the USB-C port cannot be used for ADB/PC connections. Returns false if the
     * board has no such switch (external scanner wired directly).
     */
    fun scannerPower(on: Boolean): Boolean {
        val api = commonApi ?: return false
        return try {
            val v = if (on) 1 else 0
            // 28 powers the internal USB host; 159 powers the palm module itself (vendor FP08 palm app).
            val pins = listOf(USB_HOST_GPIO, MODULE_POWER_GPIO)
            if (on) for (g in pins) { api.setGpioDir(g, 1); api.setGpioOut(g, 1) }
            val r = api.setUsbHost(v)
            Log.w(TAG, "scanner power ${if (on) "on" else "off"} -> setUsbHost=$r")
            r >= 0
        } catch (e: Throwable) {
            Log.w(TAG, "scanner power switch failed", e)
            false
        }
    }

    fun led(color: Int) {
        PalmSdk.getInstance().palmLed?.openLed(color, null)
    }

    fun connectLed(device: UsbDevice, connection: UsbDeviceConnection?) {
        PalmSdk.getInstance().connect(device, connection, null) { _, ret, _, _ ->
            Log.d(TAG, "LED controller connect result: $ret")
        }
    }

    fun calCollect(): Int = PalmSdk.getInstance().palmCalibration.collect()
    fun checkCollect(values: IntArray): String = PalmSdk.getInstance().palmCalibration.checkCollect(values).name
    fun checkCalibration(n: IntArray, near: IntArray, far: IntArray): String =
        PalmSdk.getInstance().palmCalibration.checkCalibration(n, near, far).name
    fun calibrate(n: IntArray, near: IntArray, far: IntArray) = PalmSdk.getInstance().palmCalibration.calibrate(n, near, far)
}
