package com.winlooper.netseye

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector
import androidx.media3.exoplayer.mediacodec.MediaCodecUtil
import androidx.media3.exoplayer.rtsp.RtspMediaSource
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry

/**
 * Camera streams played by Android's own media stack (Media3 / ExoPlayer):
 * RTSP in, hardware (MediaCodec) decoding, frames straight into a Flutter
 * texture. Replaces bundling libVLC and libmpv (~50 MB) and decodes every
 * camera on the video chip rather than the CPU.
 *
 * Dart side: lib/services/engines.dart (ExoEngine), channel "netseye/exo".
 */
@OptIn(UnstableApi::class)
class ExoStreams(
    private val context: Context,
    private val textures: TextureRegistry,
    private val channel: MethodChannel,
) {
    private class Stream(
        val player: ExoPlayer,
        val producer: TextureRegistry.SurfaceProducer,
        val relay: RtspRelay?,
    ) {
        var lastFrames = 0
        var stopped = false
    }

    private val streams = HashMap<Long, Stream>()
    private val main = Handler(Looper.getMainLooper())

    /** Frames-arriving heartbeat for each stream, so Dart can spot stalls. */
    private val tick = object : Runnable {
        override fun run() {
            for ((id, s) in streams) {
                if (s.stopped) continue
                val counters = s.player.videoDecoderCounters ?: continue
                counters.ensureUpdated()
                val n = counters.renderedOutputBufferCount
                if (n > s.lastFrames) {
                    s.lastFrames = n
                    send(id, "progress")
                }
            }
            if (streams.isNotEmpty()) main.postDelayed(this, 700)
        }
    }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "create" -> if (!call.argument<String>("url").orEmpty().startsWith("rtsp://")) {
                // Only camera streams: never let a bad address reach the player.
                result.error("bad_url", "Only rtsp:// camera streams are allowed", null)
            } else result.success(
                create(
                    url = call.argument<String>("url")!!,
                    tcp = call.argument<Boolean>("tcp") ?: true,
                    useRelay = call.argument<Boolean>("relay") ?: false,
                    muted = call.argument<Boolean>("muted") ?: true,
                    preferSoftware = call.argument<Boolean>("preferSoftware") ?: false,
                ),
            )
            "volume" -> {
                streams[id(call)]?.player?.volume = if (call.argument<Boolean>("muted") == true) 0f else 1f
                result.success(null)
            }
            "stop" -> {
                // Free the camera session now, but keep the texture (and so
                // the last picture) until the replacement stream is live.
                streams[id(call)]?.let {
                    it.player.release()
                    it.relay?.close()
                    it.stopped = true
                }
                result.success(null)
            }
            "dispose" -> {
                streams.remove(id(call))?.let {
                    if (!it.stopped) it.player.release()
                    it.producer.release()
                    it.relay?.close()
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun id(call: MethodCall): Long = (call.argument<Number>("id")!!).toLong()

    private fun create(url: String, tcp: Boolean, useRelay: Boolean, muted: Boolean, preferSoftware: Boolean): Long {
        val producer = textures.createSurfaceProducer()
        producer.setSize(1280, 720)
        // Live view: start as soon as a little is buffered, keep the buffer
        // short so the picture stays close to real time.
        val load = DefaultLoadControl.Builder()
            .setBufferDurationsMs(300, 1500, 150, 150)
            .setPrioritizeTimeOverSizeThresholds(true)
            .build()
        // TVs can only run a few hardware decoders at once; when they're all
        // busy, fall back to Android's built-in software decoder instead of
        // failing (grid streams are small, so that's cheap).
        // TVs often have a single hardware video decoder. Small grid streams
        // ask for the software decoder first, leaving the hardware one free
        // for the full-screen HD view.
        val selector = if (preferSoftware) {
            MediaCodecSelector { mime, secure, tunneling ->
                MediaCodecUtil.getDecoderInfos(mime, secure, tunneling).sortedBy { if (it.softwareOnly) 0 else 1 }
            }
        } else {
            MediaCodecSelector.DEFAULT
        }
        val renderers = DefaultRenderersFactory(context)
            .setMediaCodecSelector(selector)
            .setEnableDecoderFallback(true)
        val player = ExoPlayer.Builder(context, renderers).setLoadControl(load).build()
        // Only cameras whose firmware needs repairing go through the relay.
        val relay = if (tcp && useRelay) runCatching { RtspRelay(url) }.getOrNull() else null
        val source = RtspMediaSource.Factory()
            .setForceUseRtpTcp(tcp)
            .setTimeoutMs(8000)
            .createMediaSource(MediaItem.fromUri(relay?.localUrl ?: url))
        player.setMediaSource(source)
        // The audio track is always set up, even when not listening (it just
        // stays muted): some CP Plus firmware ("minirtsp") stops streaming
        // over TCP after two packets if a session has video only.
        player.volume = if (muted) 0f else 1f
        player.setVideoSurface(producer.surface)
        val id = producer.id()
        producer.setCallback(object : TextureRegistry.SurfaceProducer.Callback {
            override fun onSurfaceAvailable() = player.setVideoSurface(producer.surface)
            override fun onSurfaceCleanup() = player.setVideoSurface(null)
        })
        player.addListener(object : Player.Listener {
            override fun onVideoSizeChanged(size: VideoSize) {
                if (size.width > 0 && size.height > 0) {
                    producer.setSize(size.width, size.height)
                    send(id, "size", mapOf("w" to size.width, "h" to size.height))
                }
            }

            override fun onPlayerError(error: PlaybackException) = send(id, "error", mapOf("message" to error.errorCodeName))

            override fun onPlaybackStateChanged(state: Int) {
                if (state == Player.STATE_ENDED) send(id, "error", mapOf("message" to "ended"))
            }
        })
        player.playWhenReady = true
        player.prepare()
        val first = streams.isEmpty()
        streams[id] = Stream(player, producer, relay)
        if (first) main.postDelayed(tick, 700)
        return id
    }

    private fun send(id: Long, type: String, extra: Map<String, Any> = emptyMap()) {
        channel.invokeMethod("event", mapOf("id" to id, "type" to type) + extra)
    }

    fun releaseAll() {
        main.removeCallbacks(tick)
        for (s in streams.values) {
            if (!s.stopped) s.player.release()
            s.producer.release()
            s.relay?.close()
        }
        streams.clear()
    }
}
