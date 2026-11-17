// Copyright (c) 2026 ATC. All rights reserved.
// Proprietary and confidential. Use, copying, modification or distribution without
// written permission from ATC is prohibited. See LICENSE in the repository root.

package com.atc.palmaccess

import android.content.Context
import android.graphics.Bitmap
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.TextureView
import cn.eyecool.uvc.usb.USBMonitor
import com.google.zxing.BarcodeFormat
import com.google.zxing.BinaryBitmap
import com.google.zxing.DecodeHintType
import com.google.zxing.MultiFormatReader
import com.google.zxing.PlanarYUVLuminanceSource
import com.google.zxing.common.HybridBinarizer
import com.hfims.android.lib.palm.IPalmSdk
import com.hfims.android.lib.palm.PalmConfig
import com.hfims.android.lib.palm.PalmConst
import com.hfims.android.lib.palm.PalmSdk
import com.hfims.android.lib.palm.model.PalmCamera
import com.hfims.android.lib.palm.model.PalmTrack
import java.io.File
import java.util.EnumMap
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Process-wide owner of the VP530 SDK and the USB cameras.
 * All results are pushed to Flutter as maps through [emit].
 */
object PalmEngine {
    private const val TAG = "PalmEngine"

    data class Settings(
        val threshold: Int = 65,
        val irVid: Int = 0x1D6C,
        val irPid: Int = 0x0103,
        val rgbVid: Int = 0x2C7F,
        val rgbPid: Int = 0x4A60,
        val rotation: Int = 270,
        val mirrorH: Boolean = false,
        val mirrorV: Boolean = true,
        val qrEnabled: Boolean = false,
    )

    private lateinit var app: Context
    private val main = Handler(Looper.getMainLooper())
    private val sdkExecutor = Executors.newSingleThreadExecutor { Thread(it, "palm-sdk") }
    private val qrExecutor = Executors.newSingleThreadExecutor { Thread(it, "palm-qr") }

    var sink: ((Map<String, Any?>) -> Unit)? = null

    @Volatile var settings = Settings(); private set
    @Volatile var initState = "idle"; private set
    @Volatile var initMessage: String? = null; private set

    private lateinit var ir: UvcCamera
    private lateinit var rgb: UvcCamera
    private var initMonitor: USBMonitor? = null
    private var firstInit = true
    private var appliedConfigKey: String? = null

    @Volatile var previewWidth = UvcCamera.CAMERA_WIDTH
    @Volatile var previewHeight = UvcCamera.CAMERA_HEIGHT

    private val frameQueue = ArrayBlockingQueue<PalmCamera>(1)
    private var frameThread: Thread? = null

    @Volatile private var recognizing = false
    @Volatile private var collecting = false

    fun setup(context: Context) {
        if (::app.isInitialized) return
        app = context.applicationContext
        ir = UvcCamera(app, true)
        rgb = UvcCamera(app, false)
        ir.listener = object : UvcCamera.Listener {
            override fun onFrame(data: ByteArray, width: Int, height: Int) {
                val s = settings
                frameQueue.offer(PalmCamera(data, width, height, s.rotation, previewWidth, previewHeight, s.mirrorH, s.mirrorV))
            }
            override fun onAttachChanged(attached: Boolean) = emitCamera()
        }
        rgb.listener = object : UvcCamera.Listener {
            override fun onFrame(data: ByteArray, width: Int, height: Int) = pushQrFrame(data, width, height)
            override fun onAttachChanged(attached: Boolean) = emitCamera()
        }
        frameThread = Thread({
            while (!Thread.currentThread().isInterrupted) {
                try {
                    val frame = frameQueue.take()
                    if (PalmSdk.getInstance().isInit) PalmSdk.getInstance().setDataSource(frame, null)
                } catch (e: InterruptedException) {
                    break
                } catch (e: Throwable) {
                    Log.w(TAG, "setDataSource failed", e)
                }
            }
        }, "palm-frames").apply { isDaemon = true; start() }
    }

    fun emit(event: Map<String, Any?>) {
        main.post { sink?.invoke(event) }
    }

    private fun emitCamera() = emit(mapOf("type" to "camera", "ir" to ir.attached, "rgb" to rgb.attached))

    // ---------------------------------------------------------------- init

    fun applySettings(s: Settings) {
        settings = s
        ir.setDevice(s.irVid, s.irPid)
        rgb.setDevice(s.rgbVid, s.rgbPid)
        requestInit()
    }

    private fun configKey(s: Settings) = "${s.threshold}|${s.irVid}|${s.irPid}"

    private fun buildConfig(s: Settings): PalmConfig {
        // All SDK data (feature DB, license) stays in app-private storage, never external storage.
        val dir = File(app.filesDir, "palm").apply { mkdirs() }
        return PalmConfig.Builder()
            .recognizeThreshold(s.threshold)
            .recognizeTimes(BuildConfig.RECOGNIZE_TIMES)
            .handTypeMirror(true)
            .serverHost("") // vendor cloud matching disabled: templates never leave the device
            .irVidPid(s.irVid, s.irPid)
            .appDir(dir.absolutePath)
            .dataDbDir(app.dataDir.absolutePath)
            .sdCardDbDir(dir.absolutePath)
            .enableLog(BuildConfig.DEBUG)
            .build()
    }

    fun requestInit(force: Boolean = false) {
        val s = settings
        val key = configKey(s)
        if (!force && key == appliedConfigKey && (initState == "ready" || initState == "initializing")) return
        appliedConfigKey = key
        setInit("initializing", null)
        sdkExecutor.execute { runInit(s, 3) }
    }

    private fun runInit(s: Settings, retries: Int) {
        try {
            // FP08: the built-in scanner is unpowered until the board switch routes USB to it.
            if (PalmExtras.scannerPower(true)) Thread.sleep(1500)
            if (!firstInit) {
                try { PalmSdk.getInstance().release() } catch (_: Throwable) {}
                Thread.sleep(500)
            }
            firstInit = false
            val lock = Object()
            var done = false
            PalmSdk.getInstance().init(app, buildConfig(s), HashMap()) { success, code, message ->
                synchronized(lock) { done = true; lock.notifyAll() }
                if (success) {
                    stopInitMonitor()
                    setInit("ready", null)
                } else if (PalmConst.INIT_RESULT_NOT_FOUNT == code) {
                    setInit("no_device", message ?: "Palm module not found")
                    startInitMonitor()
                } else if (message != "Palm unauthorized" && retries > 0) {
                    sdkExecutor.execute { runInit(s, retries - 1) }
                } else {
                    setInit(if (message == "Palm unauthorized") "unauthorized" else "error", message ?: code)
                }
            }
            synchronized(lock) { if (!done) lock.wait(30_000) }
        } catch (e: Throwable) {
            Log.e(TAG, "init failed", e)
            setInit("error", e.message ?: e.javaClass.simpleName)
        }
    }

    private fun setInit(state: String, message: String?) {
        initState = state
        initMessage = message
        emit(mapOf("type" to "init", "state" to state, "message" to message))
    }

    /** When the palm module is unplugged at init time, retry automatically once it is attached. */
    private fun startInitMonitor() = main.post {
        if (initMonitor != null) return@post
        initMonitor = USBMonitor(app, object : USBMonitor.OnDeviceConnectListenerX() {
            override fun onAttach(device: UsbDevice) {
                val s = settings
                if (device.vendorId == s.irVid && device.productId == s.irPid && initState != "ready") {
                    requestInit(force = true)
                }
            }
        }).also { it.register() }
    }

    private fun stopInitMonitor() = main.post {
        initMonitor?.let { try { it.unregister(); it.destroy() } catch (_: Throwable) {} }
        initMonitor = null
    }

    // ---------------------------------------------------------------- camera / preview

    private var activeView: TextureView? = null

    fun attachPreview(irView: TextureView, rgbView: TextureView?) {
        activeView = irView
        ir.stop()
        ir.setDisplayView(irView)
        ir.start()
        if (settings.qrEnabled && rgbView != null) {
            rgb.stop()
            rgb.setDisplayView(rgbView)
            rgb.start()
        }
        emitCamera()
    }

    fun detachPreview(irView: TextureView) {
        if (activeView !== irView) return
        activeView = null
        stopRecognize()
        stopCollect()
        ir.stop()
        rgb.stop()
    }

    fun led(color: Int) = ir.led(color)

    // ---------------------------------------------------------------- recognition

    private val recognizeCallback = object : IPalmSdk.RecognizeCallback {
        override fun onPalmNull(times: Int, map: MutableMap<String, Any>?) =
            emit(mapOf("type" to "recognize", "event" to "palmNull"))

        override fun onPalmIn(tracks: MutableList<PalmTrack>?, map: MutableMap<String, Any>?) =
            emit(mapOf("type" to "recognize", "event" to "palmIn", "tracks" to tracks?.size))

        override fun onDistance(distance: Float) {}
        override fun onImage(bitmap: Bitmap?, tracks: MutableList<PalmTrack>?, map: MutableMap<String, Any>?) {}

        override fun onSuccess(palmId: String?, score: Int, map: MutableMap<String, Any>?) =
            emit(mapOf("type" to "recognize", "event" to "success", "palmId" to palmId, "score" to score))

        override fun onFailure(result: Int, score: Int, map: MutableMap<String, Any>?) =
            emit(mapOf("type" to "recognize", "event" to "failure", "result" to result, "score" to score,
                "handType" to (map?.get(PalmConst.KEY_HAND_TYPE) as? Int)))
    }

    fun startRecognize() {
        if (!PalmSdk.getInstance().isInit) return
        recognizing = true
        PalmSdk.getInstance().removeRecognizeCallback(recognizeCallback)
        PalmSdk.getInstance().addRecognizeCallback(recognizeCallback)
        PalmSdk.getInstance().startRecognize(null)
        resumeQr()
    }

    fun stopRecognize() {
        if (!recognizing) return
        recognizing = false
        try { PalmSdk.getInstance().stopRecognize() } catch (_: Throwable) {}
    }

    // ---------------------------------------------------------------- enrollment

    private val collectCallback = object : IPalmSdk.CollectCallback {
        override fun onPalmNull(times: Int, map: MutableMap<String, Any>?) =
            emit(mapOf("type" to "collect", "event" to "palmNull", "times" to times))

        override fun onPalmIn(tracks: MutableList<PalmTrack>?, map: MutableMap<String, Any>?) =
            emit(mapOf("type" to "collect", "event" to "palmIn"))

        override fun onDistance(distance: Float) {}
        override fun onImage(bitmap: Bitmap?, tracks: MutableList<PalmTrack>?, map: MutableMap<String, Any>?) {}

        override fun onSuccess(onceFeature: String?, feature: String?, palmId: String?, map: MutableMap<String, Any>?) {
            collecting = false
            emit(mapOf("type" to "collect", "event" to "success", "feature" to feature,
                "handType" to ((map?.get(PalmConst.KEY_HAND_TYPE) as? Int) ?: PalmConst.HAND_TYPE_UNKNOWN)))
        }

        override fun onFailure(result: Int, times: Int, onceFeature: String?, palmId: String?, map: MutableMap<String, Any>?) =
            emit(mapOf("type" to "collect", "event" to "failure", "result" to result, "times" to times,
                "errorCode" to (map?.get("errorCode") as? Int)))
    }

    fun startCollect(palmId: String) {
        if (!PalmSdk.getInstance().isInit) return
        collecting = true
        PalmSdk.getInstance().removeCollectCallback(collectCallback)
        PalmSdk.getInstance().addCollectCallback(collectCallback)
        PalmSdk.getInstance().startCollect(palmId, null)
    }

    fun stopCollect() {
        if (!collecting) return
        collecting = false
        try { PalmSdk.getInstance().stopCollect() } catch (_: Throwable) {}
    }

    fun maxCollectCount(): Int = try { PalmSdk.getInstance().maxCollectCount } catch (_: Throwable) { 0 }

    // ---------------------------------------------------------------- feature library

    fun addFeature(palmId: String, feature: String): Pair<Boolean, String?> {
        val r = PalmSdk.getInstance().palmLib.addFeature(palmId, feature)
        return Pair(r.first == true, r.second)
    }

    fun deleteFeature(palmId: String): Boolean = PalmSdk.getInstance().palmLib.deleteFeature(palmId)
    fun deleteAllFeatures() = PalmSdk.getInstance().palmLib.deleteAll()
    fun featureCount(): Int = try { PalmSdk.getInstance().palmLib.featureCount } catch (_: Throwable) { -1 }

    fun runOnSdk(block: () -> Unit) = sdkExecutor.execute(block)

    // ---------------------------------------------------------------- calibration

    /** Samples the IR sensor [count] times and returns the samples plus the SDK's verdict. */
    fun calibrationSample(count: Int, intervalMs: Long, step: Int): Pair<IntArray, String> {
        val values = IntArray(count)
        for (i in 0 until count) {
            values[i] = PalmExtras.calCollect()
            emit(mapOf("type" to "calibration", "step" to step, "progress" to ((i + 1) * 100 / count)))
            Thread.sleep(intervalMs)
        }
        return Pair(values, PalmExtras.checkCollect(values))
    }

    fun calibrate(nothing: IntArray, near: IntArray, far: IntArray): String {
        val verdict = PalmExtras.checkCalibration(nothing, near, far)
        if (verdict != "OK") return verdict
        ir.stopPreview()
        PalmExtras.calibrate(nothing, near, far)
        return "OK"
    }

    // ---------------------------------------------------------------- QR fallback (RGB camera)

    private val qrBusy = AtomicBoolean(false)
    @Volatile private var qrPausedUntil = 0L
    private val qrReader = MultiFormatReader().apply {
        val hints = EnumMap<DecodeHintType, Any>(DecodeHintType::class.java)
        hints[DecodeHintType.POSSIBLE_FORMATS] = listOf(BarcodeFormat.QR_CODE)
        hints[DecodeHintType.CHARACTER_SET] = "UTF-8"
        setHints(hints)
    }

    private fun resumeQr() { qrPausedUntil = 0 }
    fun pauseQr(ms: Long) { qrPausedUntil = System.currentTimeMillis() + ms }

    private fun pushQrFrame(data: ByteArray, width: Int, height: Int) {
        if (!settings.qrEnabled || !recognizing) return
        if (System.currentTimeMillis() < qrPausedUntil) return
        if (!qrBusy.compareAndSet(false, true)) return // drop frames while decoding
        val copy = data.copyOf()
        qrExecutor.execute {
            try {
                val source = PlanarYUVLuminanceSource(copy, width, height, 0, 0, width, height, false)
                val text = try {
                    qrReader.decodeWithState(BinaryBitmap(HybridBinarizer(source)))?.text
                } catch (_: Exception) { null } finally { qrReader.reset() }
                if (!text.isNullOrEmpty() && System.currentTimeMillis() >= qrPausedUntil) {
                    pauseQr(3000)
                    emit(mapOf("type" to "qr", "text" to text))
                }
            } finally {
                qrBusy.set(false)
            }
        }
    }

    // ---------------------------------------------------------------- diagnostics

    fun usbDevices(): List<Map<String, Any?>> {
        val um = app.getSystemService(Context.USB_SERVICE) as UsbManager
        return um.deviceList.values.map { d ->
            var video = false
            for (i in 0 until d.interfaceCount) if (d.getInterface(i).interfaceClass == UsbConstants.USB_CLASS_VIDEO) video = true
            mapOf("vid" to d.vendorId, "pid" to d.productId, "name" to (d.productName ?: d.deviceName),
                "manufacturer" to d.manufacturerName, "isCamera" to video)
        }
    }

    fun status(): Map<String, Any?> = mapOf(
        "initState" to initState,
        "initMessage" to initMessage,
        "irAttached" to ir.attached,
        "rgbAttached" to rgb.attached,
        "featureCount" to if (initState == "ready") featureCount() else -1,
        "deviceKey" to if (initState == "ready") try { PalmSdk.getInstance().deviceKey } catch (_: Throwable) { null } else null,
        "platform" to BuildConfig.PLATFORM,
        "recognizeTimes" to BuildConfig.RECOGNIZE_TIMES,
        "hasLedAndCalibration" to PalmExtras.SUPPORTED,
    )
}
