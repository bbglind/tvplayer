package io.github.bbglind.tvplayer

import android.content.Context
import android.media.AudioManager
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.math.roundToInt

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The touch player's volume and brightness swipes (levels 0–1).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tvplayer/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getMediaVolume" -> result.success(mediaVolume())
                    "setMediaVolume" -> {
                        setMediaVolume(call.argument<Double>("level") ?: 0.0)
                        result.success(null)
                    }
                    "getBrightness" -> result.success(brightness())
                    "setBrightness" -> {
                        setWindowBrightness(
                            (call.argument<Double>("level") ?: 0.0).toFloat().coerceIn(0.01f, 1f)
                        )
                        result.success(null)
                    }
                    "resetBrightness" -> {
                        setWindowBrightness(WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private val audio: AudioManager
        get() = getSystemService(Context.AUDIO_SERVICE) as AudioManager

    private fun mediaVolume(): Double {
        val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        if (max <= 0) return 0.0
        return audio.getStreamVolume(AudioManager.STREAM_MUSIC).toDouble() / max
    }

    // Without a flag: the app shows its own indicator, not Android's panel.
    private fun setMediaVolume(level: Double) {
        val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        val index = (level.coerceIn(0.0, 1.0) * max).roundToInt()
        audio.setStreamVolume(AudioManager.STREAM_MUSIC, index, 0)
    }

    // The window's own brightness while set, else the phone's setting.
    private fun brightness(): Double? {
        val own = window.attributes.screenBrightness
        if (own >= 0) return own.toDouble()
        return try {
            Settings.System.getInt(contentResolver, Settings.System.SCREEN_BRIGHTNESS) / 255.0
        } catch (e: Settings.SettingNotFoundException) {
            null
        }
    }

    private fun setWindowBrightness(level: Float) {
        val attributes = window.attributes
        attributes.screenBrightness = level
        window.attributes = attributes
    }
}
