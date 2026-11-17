// Copyright (c) 2026 ATC. All rights reserved.
// Proprietary and confidential. Use, copying, modification or distribution without
// written permission from ATC is prohibited. See LICENSE in the repository root.

package com.atc.palmaccess

import android.content.Context
import android.graphics.Outline
import android.view.Gravity
import android.view.TextureView
import android.view.View
import android.view.ViewGroup
import android.view.ViewOutlineProvider
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.RelativeLayout
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import kotlin.math.max
import kotlin.math.roundToInt

class PalmPreviewFactory : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        @Suppress("UNCHECKED_CAST")
        val params = args as? Map<String, Any?> ?: emptyMap()
        return PalmPreviewView(context, params["showRgb"] as? Boolean ?: false)
    }
}

/**
 * Hosts the IR preview. The UVC frame is 640x480 landscape and must be rotated to match the
 * device mounting, so the TextureView lives inside a rotated container (same approach as the
 * vendor demo). The computed on-screen size is reported to the SDK for palm-rect mapping.
 */
class PalmPreviewView(context: Context, showRgb: Boolean) : PlatformView {

    private val root = FrameLayout(context).apply {
        clipChildren = true
        clipToOutline = true
        setBackgroundColor(0xFF0B1220.toInt())
    }
    private val irView = TextureView(context)
    private val inner = RelativeLayout(context).apply { addView(irView, RelativeLayout.LayoutParams(-1, -1)) }
    private val frame = LinearLayout(context).apply { addView(inner) }
    private val rgbView: TextureView? = if (showRgb) TextureView(context) else null

    init {
        root.addView(frame, FrameLayout.LayoutParams(-2, -2))
        rgbView?.let { v ->
            val d = context.resources.displayMetrics.density
            val card = FrameLayout(context).apply {
                clipToOutline = true
                outlineProvider = object : ViewOutlineProvider() {
                    override fun getOutline(view: View, outline: Outline) =
                        outline.setRoundRect(0, 0, view.width, view.height, 12 * d)
                }
                addView(v, FrameLayout.LayoutParams(-1, -1))
            }
            root.addView(card, FrameLayout.LayoutParams((112 * d).toInt(), (84 * d).toInt(), Gravity.BOTTOM or Gravity.END)
                .apply { setMargins(0, 0, (12 * d).toInt(), (12 * d).toInt()) })
        }
        root.addOnLayoutChangeListener { _, l, t, r, b, ol, ot, or, ob ->
            if (r - l != or - ol || b - t != ob - ot) root.post { layoutPreview(r - l, b - t) }
        }
        PalmEngine.attachPreview(irView, rgbView)
    }

    private fun layoutPreview(viewW: Int, viewH: Int) {
        if (viewW <= 0 || viewH <= 0) return
        val rotation = PalmEngine.settings.rotation
        val portrait = rotation == 90 || rotation == 270
        val camW = UvcCamera.CAMERA_WIDTH
        val camH = UvcCamera.CAMERA_HEIGHT
        val screenW = if (portrait) viewH else viewW
        val screenH = if (portrait) viewW else viewH
        val scale = max(screenW.toFloat() / camW, screenH.toFloat() / camH) // center-crop
        val targetW = (camW * scale).roundToInt()
        val targetH = (camH * scale).roundToInt()

        inner.layoutParams = (inner.layoutParams ?: ViewGroup.LayoutParams(targetW, targetH)).apply {
            width = targetW; height = targetH
        }
        if (portrait) {
            inner.translationX = -((targetW - screenH) / 2.0).toFloat()
            inner.translationY = -((targetH - screenW) / 2.0).toFloat()
            frame.layoutParams = (frame.layoutParams as FrameLayout.LayoutParams).apply {
                width = max(targetH, screenH); height = max(targetW, screenW)
            }
        } else {
            inner.translationX = -((targetW - screenW) / 2.0).toFloat()
            inner.translationY = -((targetH - screenH) / 2.0).toFloat()
            frame.layoutParams = (frame.layoutParams as FrameLayout.LayoutParams).apply {
                width = screenW; height = screenH
            }
        }
        inner.rotation = rotation.toFloat()
        PalmEngine.previewWidth = targetW
        PalmEngine.previewHeight = targetH
    }

    override fun getView(): View = root

    override fun dispose() {
        PalmEngine.detachPreview(irView)
    }
}
