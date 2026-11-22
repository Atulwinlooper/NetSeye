package com.winlooper.netseye

import java.io.BufferedInputStream
import java.io.InputStream
import java.io.OutputStream
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.net.URI
import kotlin.concurrent.thread

/**
 * A tiny local RTSP relay that repairs camera quirks Android's strict RTSP
 * client rejects. Some CP Plus firmware (gvminirtsp) ends SDP lines with a
 * bare "\n" instead of "\r\n" and announces audio as payload 0 while
 * describing payload 8. The relay forwards everything byte-for-byte (video
 * is never touched), except that it fixes the stream description and maps
 * URLs between the local address and the camera.
 *
 * Over TCP only: RTP comes back interleaved on the same connection.
 */
class RtspRelay(cameraUrl: String) {
    private val camera = URI(cameraUrl)
    private val cameraBase = "rtsp://${camera.host}:${if (camera.port > 0) camera.port else 554}"
    private val server = ServerSocket(0, 4, InetAddress.getByName("127.0.0.1"))
    private val localBase = "rtsp://127.0.0.1:${server.localPort}"

    /** The URL the player should open instead of the camera's. */
    val localUrl: String = cameraUrl.replaceFirst(Regex("^rtsp://[^/]+"), localBase)

    @Volatile private var closed = false
    private val sockets = mutableListOf<Socket>()

    init {
        thread(name = "rtsp-relay-accept", isDaemon = true) {
            while (!closed) {
                val client = try { server.accept() } catch (_: Throwable) { break }
                thread(name = "rtsp-relay", isDaemon = true) { runCatching { serve(client) } }
            }
        }
    }

    /**
     * One player connection. Everything here runs on background threads, so
     * nothing may escape: a stream being closed mid-setup ("socket is
     * closed") must end this connection quietly, never the app.
     */
    private fun serve(client: Socket) {
        var upstream: Socket? = null
        try {
            if (closed) return
            // Time limits, so a camera that vanishes (Wi-Fi drop, power cut)
            // can't leave this connection's threads and sockets waiting
            // forever. A live camera sends video many times a second.
            upstream = Socket().apply {
                tcpNoDelay = true
                soTimeout = READ_TIMEOUT_MS
                connect(InetSocketAddress(camera.host, if (camera.port > 0) camera.port else 554), CONNECT_TIMEOUT_MS)
            }
            client.tcpNoDelay = true
            synchronized(sockets) { sockets += client; sockets += upstream }
            if (closed) return
            val up = upstream
            val cameraOut = up.getOutputStream()
            val reports = Reports(cameraOut)
            val toCamera = thread(name = "rtsp-relay-up", isDaemon = true) {
                runCatching {
                    pump(BufferedInputStream(client.getInputStream()), cameraOut, fromCamera = false, reports = reports)
                }
            }
            val ticker = thread(name = "rtsp-relay-rtcp", isDaemon = true) {
                runCatching {
                    while (!closed && !up.isClosed) {
                        Thread.sleep(1000)
                        reports.sendAll()
                    }
                }
            }
            pump(BufferedInputStream(up.getInputStream()), client.getOutputStream(), fromCamera = true, reports = reports)
            toCamera.interrupt()
            ticker.interrupt()
        } catch (_: Throwable) {
            // closed while connecting, camera unreachable, etc.
        } finally {
            runCatching { client.close() }
            runCatching { upstream?.close() }
            synchronized(sockets) { sockets.remove(client); upstream?.let { sockets.remove(it) } }
        }
    }

    /**
     * Copies messages one at a time. Interleaved RTP/RTCP frames ("$", channel,
     * 2-byte length) pass through untouched; RTSP text messages are rewritten.
     */
    private fun pump(input: InputStream, output: OutputStream, fromCamera: Boolean, reports: Reports) {
        try {
            while (!closed) {
                input.mark(1)
                val first = input.read()
                if (first < 0) return
                if (first == '$'.code) {
                    val header = ByteArray(3)
                    readFully(input, header)
                    val len = ((header[1].toInt() and 0xff) shl 8) or (header[2].toInt() and 0xff)
                    val payload = ByteArray(len)
                    readFully(input, payload)
                    val channel = header[0].toInt() and 0xff
                    if (fromCamera) {
                        // Note what arrived, for the receiver reports.
                        if (channel % 2 == 0) reports.onRtp(channel, payload)
                        output.write(first)
                        output.write(header)
                        output.write(payload)
                        output.flush()
                    } else {
                        synchronized(reports.lock) {
                            output.write(first)
                            output.write(header)
                            output.write(payload)
                            output.flush()
                        }
                    }
                    continue
                }
                input.reset()
                val head = readHead(input) ?: return
                val length = Regex("(?im)^content-length:\\s*(\\d+)").find(head)?.groupValues?.get(1)?.toIntOrNull() ?: 0
                // RTSP bodies are tiny (stream descriptions). Refuse anything
                // larger, so a misbehaving device can't exhaust memory.
                if (length > MAX_BODY) return
                var body = ByteArray(length).also { readFully(input, it) }
                var text = head
                if (fromCamera) {
                    text = text.replace(cameraBase, localBase)
                    if (Regex("(?im)^content-type:\\s*application/sdp").containsMatchIn(head)) {
                        body = fixSdp(String(body, Charsets.ISO_8859_1)).toByteArray(Charsets.ISO_8859_1)
                        text = text.replace(Regex("(?im)^content-length:\\s*\\d+"), "Content-Length: ${body.size}")
                    }
                } else {
                    text = text.replace(localBase, cameraBase)
                }
                synchronized(reports.lock) {
                    output.write(text.toByteArray(Charsets.ISO_8859_1))
                    output.write(body)
                    output.flush()
                }
            }
        } catch (_: Exception) {
            // connection closed
        }
    }

    /** Reads up to and including the blank line that ends RTSP headers. */
    private fun readHead(input: InputStream): String? {
        val sb = StringBuilder()
        while (true) {
            val b = input.read()
            if (b < 0) return null
            sb.append(b.toChar())
            if (sb.endsWith("\r\n\r\n") || sb.endsWith("\n\n")) return sb.toString()
            if (sb.length > 16384) return null
        }
    }

    private fun readFully(input: InputStream, buf: ByteArray) {
        var off = 0
        while (off < buf.size) {
            val n = input.read(buf, off, buf.size - off)
            if (n < 0) throw java.io.EOFException()
            off += n
        }
    }

    /**
     * RTCP receiver reports, sent to the camera on the player's behalf over
     * the RTSP connection. Android's player sends none, and some CP Plus
     * firmware ("minirtsp") stops streaming after a few packets without
     * them (ffmpeg / VLC send them, which is why those always worked).
     */
    private class Reports(private val cameraOut: OutputStream) {
        val lock = Any()
        private val ourSsrc = (Math.random() * Int.MAX_VALUE).toInt()

        private class Source(val ssrc: Int) {
            var maxSeq = -1
            var cycles = 0
        }

        private val sources = HashMap<Int, Source>() // by RTP channel
        private var sentFirst = HashSet<Int>()

        fun onRtp(channel: Int, rtp: ByteArray) {
            if (rtp.size < 12) return
            val seq = ((rtp[2].toInt() and 0xff) shl 8) or (rtp[3].toInt() and 0xff)
            val ssrc = ((rtp[8].toInt() and 0xff) shl 24) or ((rtp[9].toInt() and 0xff) shl 16) or
                ((rtp[10].toInt() and 0xff) shl 8) or (rtp[11].toInt() and 0xff)
            val first: Boolean
            synchronized(sources) {
                val src = sources[channel]?.takeIf { it.ssrc == ssrc } ?: Source(ssrc).also { sources[channel] = it }
                if (src.maxSeq < 0) {
                    src.maxSeq = seq
                } else if (seq > src.maxSeq || src.maxSeq - seq > 30000) {
                    if (seq < src.maxSeq) src.cycles++
                    src.maxSeq = seq
                }
                first = sentFirst.add(channel)
            }
            if (first) send(channel) // answer straight away, then every second
        }

        fun sendAll() {
            val channels = synchronized(sources) { sources.keys.toList() }
            channels.forEach { send(it) }
        }

        private fun send(channel: Int) {
            val src = synchronized(sources) { sources[channel] } ?: return
            val packet = java.nio.ByteBuffer.allocate(52)
            // Receiver report: V=2, 1 report block, PT=201, length 7.
            packet.put(0x81.toByte()).put(201.toByte()).putShort(7).putInt(ourSsrc)
            packet.putInt(src.ssrc)
            packet.putInt(0) // fraction lost + cumulative lost
            packet.putInt((src.cycles shl 16) or src.maxSeq)
            packet.putInt(0).putInt(0).putInt(0) // jitter, LSR, DLSR
            // SDES with a CNAME, as RFC 3550 compound packets require.
            packet.put(0x81.toByte()).put(202.toByte()).putShort(4).putInt(ourSsrc)
            packet.put(1).put(7).put("netseye".toByteArray()).put(0).put(0).put(0)
            val bytes = packet.array()
            synchronized(lock) {
                runCatching {
                    cameraOut.write('$'.code)
                    cameraOut.write(channel + 1) // RTCP channel follows the RTP one
                    cameraOut.write(bytes.size shr 8)
                    cameraOut.write(bytes.size and 0xff)
                    cameraOut.write(bytes)
                    cameraOut.flush()
                }
            }
        }
    }

    companion object {
        private const val MAX_BODY = 64 * 1024
        private const val CONNECT_TIMEOUT_MS = 5000
        private const val READ_TIMEOUT_MS = 15000

        /** Normalises line endings and mismatched audio payload numbers. */
        fun fixSdp(sdp: String): String {
            val lines = sdp.split(Regex("\r?\n")).filter { it.isNotEmpty() }
            val out = mutableListOf<String>()
            var mediaPt: String? = null
            for (line in lines) {
                var l = line.trimEnd()
                if (l.startsWith("m=")) {
                    val parts = l.split(" ")
                    mediaPt = if (parts.size == 4) parts[3] else null
                } else if (mediaPt != null && l.startsWith("a=rtpmap:")) {
                    val pt = l.substringAfter("a=rtpmap:").substringBefore(" ")
                    if (pt != mediaPt) {
                        // e.g. m=audio ... 0 with a=rtpmap:8 PCMU: trust the codec name.
                        val codec = l.substringAfter(" ").uppercase()
                        val staticPt = when {
                            codec.startsWith("PCMU") -> "0"
                            codec.startsWith("PCMA") -> "8"
                            else -> mediaPt
                        }
                        l = "a=rtpmap:$staticPt " + l.substringAfter(" ")
                        if (staticPt != mediaPt) out[out.indexOfLast { it.startsWith("m=") }] =
                            out[out.indexOfLast { it.startsWith("m=") }].replaceAfterLast(" ", staticPt)
                        mediaPt = staticPt
                    }
                }
                out += l
            }
            return out.joinToString("\r\n", postfix = "\r\n")
        }
    }

    fun close() {
        closed = true
        runCatching { server.close() }
        synchronized(sockets) { sockets.forEach { runCatching { it.close() } }; sockets.clear() }
    }
}
