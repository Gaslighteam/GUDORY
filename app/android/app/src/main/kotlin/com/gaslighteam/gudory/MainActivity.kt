package com.gaslighteam.gudory

import android.media.MediaActionSound
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // The system camera shutter sound, same as the stock camera app. Where
    // the region requires it (e.g. Korea), Android plays it even in silent
    // mode.
    private val shutterSound = MediaActionSound().apply {
        load(MediaActionSound.SHUTTER_CLICK)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "gudory/shutter")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "play" -> {
                        shutterSound.play(MediaActionSound.SHUTTER_CLICK)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        shutterSound.release()
        super.onDestroy()
    }
}
