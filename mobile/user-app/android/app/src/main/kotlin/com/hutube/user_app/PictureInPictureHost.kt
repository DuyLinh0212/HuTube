package com.hutube.user_app

import android.app.Activity
import android.app.PictureInPictureParams
import android.content.pm.PackageManager
import android.os.Build
import android.util.Rational
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

class PictureInPictureHost(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "hutube/picture_in_picture")
    private var automatic = false
    private var preparing = false
    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "available" -> result.success(available())
                "enter" -> result.success(enter())
                "configure" -> {
                    automatic = call.argument<Boolean>("automatic") == true
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
    private fun available() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
        activity.packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
    private fun enter(): Boolean {
        if (!available() || activity.isFinishing) return false
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                activity.enterPictureInPictureMode(PictureInPictureParams.Builder()
                    .setAspectRatio(Rational(16, 9)).build())
            } else false
        } catch (_: Exception) { false }
    }
    fun onUserLeaveHint() {
        if (!automatic || preparing || !available()) return
        preparing = true
        channel.invokeMethod("prepare", null, object : MethodChannel.Result {
            override fun success(result: Any?) {
                preparing = false
                if (automatic && result == true) enter()
            }
            override fun error(code: String, message: String?, details: Any?) { preparing = false }
            override fun notImplemented() { preparing = false }
        })
    }
    fun close() { automatic = false; channel.setMethodCallHandler(null) }
}
