// Copyright (c) 2026 ATC. All rights reserved.
// Proprietary and confidential. Use, copying, modification or distribution without
// written permission from ATC is prohibited. See LICENSE in the repository root.

package com.atc.palmaccess

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Starts the access terminal after the device boots, when the admin enabled "Start on boot".
 * Android 10+ only allows this for the default home app, so enable "Dedicated device" mode too.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        val prefs = context.getSharedPreferences("atc_native", Context.MODE_PRIVATE)
        if (!prefs.getBoolean("boot_start", false)) return
        context.startActivity(
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
    }
}
