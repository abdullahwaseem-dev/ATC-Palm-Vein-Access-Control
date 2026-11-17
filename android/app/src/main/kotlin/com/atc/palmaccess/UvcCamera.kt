// Copyright (c) 2026 ATC. All rights reserved.
// Proprietary and confidential. Use, copying, modification or distribution without
// written permission from ATC is prohibited. See LICENSE in the repository root.

package com.atc.palmaccess

import android.content.Context
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.os.Handler
import android.util.Log
import android.view.TextureView
import cn.eyecool.uvc.usb.USBMonitor
import cn.eyecool.uvc.usb.UVCCamera
import cn.eyecool.uvc.usb.UVCCameraManager
import cn.eyecool.uvc.util.HandlerThreadHandler

/**
 * One USB (UVC) camera bound to a VID/PID. Ported from the vendor demo's CameraHelp.
 * The IR instance also connects the VP530 LED controller once preview starts.
 */
class UvcCamera(context: Context, private val isIr: Boolean) {

    interface Listener {
        fun onFrame(data: ByteArray, width: Int, height: Int)
        fun onAttachChanged(attached: Boolean)
    }

    @Volatile var vid = 0; private set
    @Volatile var pid = 0; private set
    @Volatile var listener: Listener? = null
    @Volatile private var started = false
    @Volatile var attached = false; private set

    private val tag = if (isIr) "UvcCamera-IR" else "UvcCamera-RGB"
    private val workHandler: Handler = HandlerThreadHandler.createHandler(tag)
    private val manager = UVCCameraManager(context.applicationContext)

    private val monitor: USBMonitor = USBMonitor(context.applicationContext, object : USBMonitor.OnDeviceConnectListener {
        override fun onAttach(device: UsbDevice) {
            if (matches(device)) {
                monitor.requestPermission(device)
                setAttached(true)
            }
        }

        override fun onDettach(device: UsbDevice) {
            if (matches(device)) {
                close()
                setAttached(false)
            }
        }

        override fun onConnect(device: UsbDevice, ctrlBlock: USBMonitor.UsbControlBlock, createNew: Boolean) {
            if (matches(device)) workHandler.post { open(ctrlBlock) }
        }

        override fun onDisconnect(device: UsbDevice, ctrlBlock: USBMonitor.UsbControlBlock) {
            if (matches(device)) close()
        }

        override fun onCancel(device: UsbDevice) {
            Log.w(tag, "USB permission denied")
        }
    })

    init {
        manager.setUVCCameraCallback(object : UVCCameraManager.UVCCameraCallbackX() {
            override fun afterOpen(camera: UVCCamera) {
                manager.setPreviewSize(CAMERA_WIDTH, CAMERA_HEIGHT)
            }

            override fun beforePreview(camera: UVCCamera) {
                super.beforePreview(camera)
                camera.openImage()
            }

            override fun afterPreview(camera: UVCCamera) {
                super.afterPreview(camera)
                camera.updateCameraParams()
                if (isIr) connectLed(camera)
            }

            override fun onOpened() {}
            override fun onPreview() {}
            override fun onOpenError(code: Int) {
                Log.w(tag, "open error $code")
            }
        })
    }

    private fun matches(d: UsbDevice) = d.vendorId == vid && d.productId == pid

    private fun setAttached(value: Boolean) {
        attached = value
        listener?.onAttachChanged(value)
    }

    private fun open(ctrlBlock: USBMonitor.UsbControlBlock) {
        manager.setPreviewCallback { bytes, w, h -> listener?.onFrame(bytes, w, h) }
        workHandler.post { manager.openCamera(ctrlBlock) }
    }

    private fun close() {
        workHandler.post { manager.closeCamera() }
    }

    fun setDisplayView(view: TextureView) = manager.setDisplayView(view)

    /** Returns true when the device binding changed. */
    fun setDevice(vid: Int, pid: Int): Boolean {
        if (this.vid == vid && this.pid == pid) return false
        this.vid = vid
        this.pid = pid
        if (started) {
            stop()
            start()
        }
        return true
    }

    fun start() {
        started = true
        monitor.register()
    }

    fun stop() {
        started = false
        try { monitor.unregister() } catch (_: Exception) {}
        close()
    }

    fun stopPreview() {
        workHandler.post { manager.stopPreview() }
    }

    fun led(color: Int) {
        workHandler.post {
            try {
                PalmExtras.led(color)
            } catch (e: Throwable) {
                Log.w(tag, "LED failed", e)
            }
        }
    }

    private fun connectLed(camera: UVCCamera) {
        try {
            PalmExtras.connectLed(camera.device, connectionOf(camera))
        } catch (e: Throwable) {
            Log.w(tag, "LED controller connect failed", e)
        }
    }

    /** The vendor library hides the USB connection; the demo reads it via reflection too. */
    private fun connectionOf(camera: UVCCamera): UsbDeviceConnection? = try {
        val f = UVCCamera::class.java.getDeclaredField("mCtrlBlock")
        f.isAccessible = true
        (f.get(camera) as? USBMonitor.UsbControlBlock)?.connection
    } catch (e: Exception) {
        null
    }

    companion object {
        const val CAMERA_WIDTH = 640
        const val CAMERA_HEIGHT = 480
        // PalmConst.PALM_LED_* values (only defined in the MTK SDK)
        const val LED_WHITE = 0
        const val LED_RED = 1
        const val LED_GREEN = 2
    }
}
