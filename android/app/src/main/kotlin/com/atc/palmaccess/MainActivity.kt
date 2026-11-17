// Copyright (c) 2026 ATC. All rights reserved.
// Proprietary and confidential. Use, copying, modification or distribution without
// written permission from ATC is prohibited. See LICENSE in the repository root.

package com.atc.palmaccess

import android.app.ActivityManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {

    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newFixedThreadPool(2)
    private var tone: ToneGenerator? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Admin screens show personal data: keep them out of screenshots / the recents thumbnail.
        if (!BuildConfig.ALLOW_SCREENSHOTS) window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        PalmEngine.setup(this)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        flutterEngine.platformViewsController.registry
            .registerViewFactory("atc/palm_preview", PalmPreviewFactory())

        EventChannel(messenger, "atc/palm/events").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(args: Any?, events: EventChannel.EventSink) {
                PalmEngine.sink = { events.success(it) }
            }
            override fun onCancel(args: Any?) {
                PalmEngine.sink = null
            }
        })

        MethodChannel(messenger, "atc/palm").setMethodCallHandler { call, result -> handlePalm(call, result) }
        MethodChannel(messenger, "atc/device").setMethodCallHandler { call, result -> handleDevice(call, result) }
    }

    /** Runs [block] off the UI thread and replies on the UI thread. */
    private fun async(result: MethodChannel.Result, block: () -> Any?) {
        worker.execute {
            try {
                val v = block()
                main.post { result.success(v) }
            } catch (e: Throwable) {
                main.post { result.error("ERR", e.message ?: e.javaClass.simpleName, null) }
            }
        }
    }

    private fun sdk(result: MethodChannel.Result, block: () -> Any?) {
        PalmEngine.runOnSdk {
            try {
                val v = block()
                main.post { result.success(v) }
            } catch (e: Throwable) {
                main.post { result.error("ERR", e.message ?: e.javaClass.simpleName, null) }
            }
        }
    }

    private fun handlePalm(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "configure" -> {
                val d = PalmEngine.Settings()
                PalmEngine.applySettings(
                    PalmEngine.Settings(
                        threshold = (call.argument<Int>("threshold") ?: d.threshold).coerceIn(40, 95),
                        irVid = call.argument<Int>("irVid") ?: d.irVid,
                        irPid = call.argument<Int>("irPid") ?: d.irPid,
                        rgbVid = call.argument<Int>("rgbVid") ?: d.rgbVid,
                        rgbPid = call.argument<Int>("rgbPid") ?: d.rgbPid,
                        rotation = call.argument<Int>("rotation") ?: d.rotation,
                        mirrorH = call.argument<Boolean>("mirrorH") ?: d.mirrorH,
                        mirrorV = call.argument<Boolean>("mirrorV") ?: d.mirrorV,
                        qrEnabled = call.argument<Boolean>("qrEnabled") ?: d.qrEnabled,
                    )
                )
                result.success(null)
            }
            "reinit" -> { PalmEngine.requestInit(force = true); result.success(null) }
            "status" -> async(result) { PalmEngine.status() }
            "startRecognize" -> { PalmEngine.startRecognize(); result.success(null) }
            "stopRecognize" -> { PalmEngine.stopRecognize(); result.success(null) }
            "startCollect" -> { PalmEngine.startCollect(call.argument<String>("palmId")!!); result.success(null) }
            "stopCollect" -> { PalmEngine.stopCollect(); result.success(null) }
            "maxCollectCount" -> result.success(PalmEngine.maxCollectCount())
            "led" -> {
                val color = when (call.argument<String>("color")) {
                    "green" -> UvcCamera.LED_GREEN
                    "red" -> UvcCamera.LED_RED
                    else -> UvcCamera.LED_WHITE
                }
                PalmEngine.led(color); result.success(null)
            }
            "pauseQr" -> { PalmEngine.pauseQr((call.argument<Int>("ms") ?: 3000).toLong()); result.success(null) }
            "addFeature" -> sdk(result) {
                val r = PalmEngine.addFeature(call.argument<String>("palmId")!!, call.argument<String>("feature")!!)
                mapOf("ok" to r.first, "message" to r.second)
            }
            "deleteFeature" -> sdk(result) { PalmEngine.deleteFeature(call.argument<String>("palmId")!!) }
            "deleteAllFeatures" -> sdk(result) { PalmEngine.deleteAllFeatures(); true }
            "featureCount" -> sdk(result) { PalmEngine.featureCount() }
            "calibrationSample" -> sdk(result) {
                val r = PalmEngine.calibrationSample(call.argument<Int>("count") ?: 20,
                    (call.argument<Int>("interval") ?: 100).toLong(), call.argument<Int>("step") ?: 1)
                mapOf("values" to r.first.toList(), "verdict" to r.second)
            }
            "calibrate" -> sdk(result) {
                fun arr(k: String) = call.argument<List<Int>>(k)!!.toIntArray()
                PalmEngine.calibrate(arr("nothing"), arr("near"), arr("far"))
            }
            "usbDevices" -> async(result) { PalmEngine.usbDevices() }
            else -> result.notImplemented()
        }
    }

    private fun prefs() = getSharedPreferences("atc_native", Context.MODE_PRIVATE)

    private fun handleDevice(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            // --- crypto (Keystore-backed)
            "encrypt" -> async(result) { SecureVault.encrypt(call.argument<String>("plain")!!) }
            "decrypt" -> async(result) { SecureVault.decrypt(call.argument<String>("token")!!) }
            "decryptMany" -> async(result) { call.argument<List<String>>("tokens")!!.map { SecureVault.decrypt(it) } }
            "hashPin" -> async(result) { SecureVault.hashPin(call.argument<String>("pin")!!) }
            "verifyPin" -> async(result) { SecureVault.verifyPin(call.argument<String>("pin")!!, call.argument<String>("hash")!!) }
            "encryptBackup" -> async(result) {
                SecureVault.encryptBackup(call.argument<String>("plain")!!, call.argument<String>("password")!!)
            }
            "decryptBackup" -> async(result) {
                SecureVault.decryptBackup(call.argument<String>("salt")!!, call.argument<String>("iv")!!,
                    call.argument<String>("data")!!, call.argument<Int>("iterations")!!, call.argument<String>("password")!!)
            }
            "randomToken" -> result.success(SecureVault.randomToken(call.argument<Int>("bytes") ?: 32))
            "hmac" -> result.success(SecureVault.hmacSha256Hex(call.argument<String>("key")!!, call.argument<String>("message")!!))

            // --- kiosk / dedicated device
            "startKiosk" -> { try { startLockTask(); result.success(true) } catch (e: Exception) { result.success(false) } }
            "stopKiosk" -> { try { stopLockTask(); result.success(true) } catch (e: Exception) { result.success(false) } }
            "isKiosk" -> {
                val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                result.success(am.lockTaskModeState != ActivityManager.LOCK_TASK_MODE_NONE)
            }
            "setLauncherMode" -> {
                val enabled = call.argument<Boolean>("enabled") == true
                packageManager.setComponentEnabledSetting(
                    ComponentName(this, "$packageName.LauncherAlias"),
                    if (enabled) PackageManager.COMPONENT_ENABLED_STATE_ENABLED else PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                    PackageManager.DONT_KILL_APP
                )
                result.success(true)
            }
            "isLauncherMode" -> result.success(
                packageManager.getComponentEnabledSetting(ComponentName(this, "$packageName.LauncherAlias")) ==
                    PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            )
            "openHomeSettings" -> {
                try { startActivity(Intent(Settings.ACTION_HOME_SETTINGS)) } catch (_: Exception) {
                    startActivity(Intent(Settings.ACTION_SETTINGS))
                }
                result.success(null)
            }
            "setBootStart" -> { prefs().edit().putBoolean("boot_start", call.argument<Boolean>("enabled") == true).apply(); result.success(null) }

            // --- feedback
            "tone" -> {
                try {
                    val t = tone ?: ToneGenerator(AudioManager.STREAM_NOTIFICATION, 90).also { tone = it }
                    when (call.argument<String>("kind")) {
                        "granted" -> t.startTone(ToneGenerator.TONE_PROP_ACK, 220)
                        "denied" -> t.startTone(ToneGenerator.TONE_SUP_ERROR, 450)
                        else -> t.startTone(ToneGenerator.TONE_PROP_BEEP, 120)
                    }
                } catch (_: Exception) {}
                result.success(null)
            }
            "deviceInfo" -> result.success(
                mapOf(
                    "model" to Build.MODEL, "manufacturer" to Build.MANUFACTURER, "android" to Build.VERSION.RELEASE,
                    "sdkInt" to Build.VERSION.SDK_INT, "hardware" to Build.HARDWARE, "platform" to BuildConfig.PLATFORM,
                    "appVersion" to BuildConfig.VERSION_NAME, "build" to BuildConfig.VERSION_CODE,
                )
            )
            else -> result.notImplemented()
        }
    }

    override fun onDestroy() {
        // Hand the USB port back (as the vendor app does) only when the app is really closing.
        if (isFinishing) PalmEngine.runOnSdk { PalmExtras.scannerPower(false) }
        tone?.release()
        tone = null
        super.onDestroy()
    }
}
