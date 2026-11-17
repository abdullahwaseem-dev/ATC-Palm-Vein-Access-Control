// Copyright (c) 2026 ATC. All rights reserved.
// Proprietary and confidential. Use, copying, modification or distribution without
// written permission from ATC is prohibited. See LICENSE in the repository root.

package com.atc.palmaccess

import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection

/** Rockchip SDK (v2.2.11) has no LED or calibration API: these are no-ops and the UI hides them. */
object PalmExtras {
    const val SUPPORTED = false
    fun scannerPower(on: Boolean): Boolean = false
    fun led(color: Int) {}
    fun connectLed(device: UsbDevice, connection: UsbDeviceConnection?) {}
    fun calCollect(): Int = throw UnsupportedOperationException("Calibration is not supported by this scanner SDK")
    fun checkCollect(values: IntArray): String = "INVALID"
    fun checkCalibration(n: IntArray, near: IntArray, far: IntArray): String = "INCOMPLETE"
    fun calibrate(n: IntArray, near: IntArray, far: IntArray) {}
}
