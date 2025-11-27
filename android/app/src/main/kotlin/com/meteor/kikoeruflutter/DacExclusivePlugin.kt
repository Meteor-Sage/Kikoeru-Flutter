package com.meteor.kikoeruflutter

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * Handles Android DAC exclusive mode via audio focus requests.
 */
class DacExclusivePlugin(private val context: Context) : MethodCallHandler {
    companion object {
        const val CHANNEL = "com.kikoeru.flutter/dac_exclusive"
    }

    private val audioManager =
        context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val focusChangeListener =
        AudioManager.OnAudioFocusChangeListener { /* no-op */ }
    private var audioFocusRequest: AudioFocusRequest? = null
    private var isExclusive = false

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "isSupported" -> result.success(isSupported())
            "enable" -> result.success(enableExclusive())
            "disable" -> {
                disableExclusive()
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private fun isSupported(): Boolean {
        // Require Android 8.0+ so AudioFocusRequest is available.
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
    }

    private fun enableExclusive(): Boolean {
        if (!isSupported()) {
            isExclusive = false
            return false
        }

        if (isExclusive) {
            return true
        }

        val requestResult = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val attributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                .build()

            audioFocusRequest = AudioFocusRequest.Builder(
                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE
            )
                .setAcceptsDelayedFocusGain(false)
                .setAudioAttributes(attributes)
                .setOnAudioFocusChangeListener(focusChangeListener)
                .build()

            audioManager.requestAudioFocus(audioFocusRequest!!)
        } else {
            @Suppress("DEPRECATION")
            audioManager.requestAudioFocus(
                focusChangeListener,
                AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE
            )
        }

        isExclusive = requestResult == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        return isExclusive
    }

    private fun disableExclusive() {
        if (!isExclusive) return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            audioFocusRequest?.let { request ->
                audioManager.abandonAudioFocusRequest(request)
            }
            audioFocusRequest = null
        } else {
            @Suppress("DEPRECATION")
            audioManager.abandonAudioFocus(focusChangeListener)
        }

        isExclusive = false
    }

    fun cleanup() {
        disableExclusive()
    }
}
