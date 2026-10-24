package com.hutube.user_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var mediaTools: MediaTools? = null
    private var deviceConditions: DeviceConditions? = null
    private var pictureInPicture: PictureInPictureHost? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        mediaTools = MediaTools(this, flutterEngine.dartExecutor.binaryMessenger)
        deviceConditions = DeviceConditions(this, flutterEngine.dartExecutor.binaryMessenger)
        pictureInPicture = PictureInPictureHost(this, flutterEngine.dartExecutor.binaryMessenger)
    }
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        pictureInPicture?.onUserLeaveHint()
    }
    override fun onDestroy() {
        mediaTools?.close()
        mediaTools = null
        deviceConditions?.close()
        deviceConditions = null
        pictureInPicture?.close()
        pictureInPicture = null
        super.onDestroy()
    }
}
