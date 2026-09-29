package com.translatelanguage.app

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.math.max

/**
 * Plays live call PCM on the voice-communication path so Android's
 * hardware acoustic echo canceller can subtract it from the mic.
 */
class PcmPlayerPlugin(
    private val engine: FlutterEngine,
    private val context: Context,
) : MethodChannel.MethodCallHandler {
    private var track: AudioTrack? = null
    private var focusRequest: AudioFocusRequest? = null

    override fun onMethodCall(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                val sampleRate = call.argument<Int>("sampleRate") ?: 16000
                applyCallAudio(speakerOn = true)
                val minBuf = AudioTrack.getMinBufferSize(
                    sampleRate,
                    AudioFormat.CHANNEL_OUT_MONO,
                    AudioFormat.ENCODING_PCM_16BIT,
                )
                val buf = max(minBuf, sampleRate * 2 / 8)
                track?.release()
                track = buildTrack(sampleRate, buf, AudioAttributes.USAGE_VOICE_COMMUNICATION)
                track?.setVolume(1.0f)
                track?.play()
                result.success(null)
            }
            "write" -> {
                val bytes = call.argument<ByteArray>("bytes") ?: ByteArray(0)
                track?.write(bytes, 0, bytes.size, AudioTrack.WRITE_NON_BLOCKING)
                result.success(null)
            }
            "flush" -> {
                track?.pause()
                track?.flush()
                track?.play()
                result.success(null)
            }
            "stop" -> {
                track?.stop()
                track?.release()
                track = null
                releaseCallAudio()
                result.success(null)
            }
            "setSpeaker" -> {
                val on = call.argument<Boolean>("on") ?: true
                applyCallAudio(speakerOn = on)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun applyCallAudio(speakerOn: Boolean) {
        val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        am.mode = AudioManager.MODE_IN_COMMUNICATION
        @Suppress("DEPRECATION")
        am.isSpeakerphoneOn = speakerOn
        val attrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(attrs)
                .build()
            focusRequest = req
            am.requestAudioFocus(req)
        } else {
            @Suppress("DEPRECATION")
            am.requestAudioFocus(null, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN)
        }
    }

    private fun releaseCallAudio() {
        val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            focusRequest?.let { am.abandonAudioFocusRequest(it) }
        } else {
            @Suppress("DEPRECATION")
            am.abandonAudioFocus(null)
        }
        focusRequest = null
        @Suppress("DEPRECATION")
        am.isSpeakerphoneOn = false
        am.mode = AudioManager.MODE_NORMAL
    }

    companion object {
        fun register(engine: FlutterEngine, context: Context) {
            val plugin = PcmPlayerPlugin(engine, context.applicationContext)
            MethodChannel(engine.dartExecutor.binaryMessenger, "translatelanguage/pcm_player")
                .setMethodCallHandler(plugin)
        }
    }

    private fun buildTrack(sampleRate: Int, buf: Int, usage: Int): AudioTrack {
        return AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(usage)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build(),
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(sampleRate)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build(),
            )
            .setBufferSizeInBytes(buf)
            .setTransferMode(AudioTrack.MODE_STREAM)
            .build()
    }
}
