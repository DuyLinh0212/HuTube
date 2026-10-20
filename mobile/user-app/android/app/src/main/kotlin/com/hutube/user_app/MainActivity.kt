package com.hutube.user_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var mediaTools: MediaTools? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        mediaTools = MediaTools(this, flutterEngine.dartExecutor.binaryMessenger)
    }
    override fun onDestroy() {
        mediaTools?.close()
        mediaTools = null
        super.onDestroy()
    }
}
