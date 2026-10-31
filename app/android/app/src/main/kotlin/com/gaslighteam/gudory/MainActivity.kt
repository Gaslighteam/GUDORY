package com.gaslighteam.gudory

import android.media.AudioAttributes
import android.media.MediaActionSound
import android.media.SoundPool
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    // The system camera shutter sound, the same file and audio attributes
    // MediaActionSound uses, so it stays audible in silent mode where the
    // region requires it (e.g. Korea). Played through our own SoundPool only
    // to make it a little quieter; MediaActionSound has no volume control.
    private val shutterPool = SoundPool.Builder()
        .setMaxStreams(1)
        .setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .setFlags(AudioAttributes.FLAG_AUDIBILITY_ENFORCED)
                .build()
        )
        .build()
    private val shutterId: Int? = listOf(
        "/product/media/audio/ui/camera_click.ogg",
        "/system/media/audio/ui/camera_click.ogg",
    ).firstOrNull { File(it).canRead() }?.let { shutterPool.load(it, 1) }

    // Fallback when the sound file isn't where AOSP keeps it.
    private val fallback by lazy {
        MediaActionSound().apply { load(MediaActionSound.SHUTTER_CLICK) }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "gudory/shutter")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "play" -> {
                        val played = shutterId?.let {
                            shutterPool.play(it, VOLUME, VOLUME, 1, 0, 1f) != 0
                        } ?: false
                        if (!played) fallback.play(MediaActionSound.SHUTTER_CLICK)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        shutterPool.release()
        super.onDestroy()
    }

    private companion object {
        /** A little under the stock camera's full-volume click. */
        const val VOLUME = 0.6f
    }
}
