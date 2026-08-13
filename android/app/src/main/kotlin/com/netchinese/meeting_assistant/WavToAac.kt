package com.netchinese.meeting_assistant

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import java.io.File
import java.io.FileInputStream

/**
 * 把錄音的 WAV(16kHz / mono / 16-bit PCM)編碼成 m4a(AAC)。
 *
 * 為什麼要轉:一小時 WAV 約 110MB —— 佔手機空間,且大到無法用通訊軟體傳送。
 * 轉成 AAC 後約 9MB(壓縮約 12 倍),對語音而言音質足夠。
 *
 * 用系統 MediaCodec/MediaMuxer 而非引入 ffmpeg:無額外原生依賴與編譯風險。
 */
object WavToAac {
    private const val TIMEOUT_US = 10_000L

    /**
     * @param bitRate AAC 位元率,由 Dart 端指定(會依序嘗試 48k/32k/24k)。
     *   AAC 對低取樣率有位元率上限,超過會整個編碼失敗 —— 實測 16kHz 單聲道
     *   最高約 48000(實際輸出約 31.5kbps),64000 不支援。見
     *   lib/services/audio_convert.dart。
     */
    fun convert(srcPath: String, dstPath: String, bitRate: Int = 48_000): Boolean {
        val src = File(srcPath)
        if (!src.exists()) return false
        File(dstPath).delete()

        FileInputStream(src).use { input ->
            val header = ByteArray(44)
            if (input.read(header) != 44) return false
            val (sampleRate, channels) = parseWavHeader(header) ?: return false

            val format = MediaFormat.createAudioFormat(
                MediaFormat.MIMETYPE_AUDIO_AAC, sampleRate, channels
            ).apply {
                setInteger(
                    MediaFormat.KEY_AAC_PROFILE,
                    MediaCodecInfo.CodecProfileLevel.AACObjectLC
                )
                setInteger(MediaFormat.KEY_BIT_RATE, bitRate)
            }

            val codec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
            codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            codec.start()

            val muxer = MediaMuxer(dstPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            var trackIndex = -1
            var muxerStarted = false
            val bufferInfo = MediaCodec.BufferInfo()
            val chunk = ByteArray(4096)
            var totalRead = 0L
            var inputDone = false

            try {
                while (true) {
                    if (!inputDone) {
                        val inIndex = codec.dequeueInputBuffer(TIMEOUT_US)
                        if (inIndex >= 0) {
                            val buf = codec.getInputBuffer(inIndex)!!
                            buf.clear()
                            val read = input.read(chunk, 0, minOf(chunk.size, buf.remaining()))
                            if (read <= 0) {
                                codec.queueInputBuffer(
                                    inIndex, 0, 0, presentationTime(totalRead, sampleRate, channels),
                                    MediaCodec.BUFFER_FLAG_END_OF_STREAM
                                )
                                inputDone = true
                            } else {
                                buf.put(chunk, 0, read)
                                codec.queueInputBuffer(
                                    inIndex, 0, read,
                                    presentationTime(totalRead, sampleRate, channels), 0
                                )
                                totalRead += read
                            }
                        }
                    }

                    val outIndex = codec.dequeueOutputBuffer(bufferInfo, TIMEOUT_US)
                    when {
                        outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                            if (!muxerStarted) {
                                trackIndex = muxer.addTrack(codec.outputFormat)
                                muxer.start()
                                muxerStarted = true
                            }
                        }
                        outIndex >= 0 -> {
                            val encoded: java.nio.ByteBuffer = codec.getOutputBuffer(outIndex)!!
                            // codec config 不寫入 muxer(格式資訊已由 addTrack 帶入)
                            if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) {
                                bufferInfo.size = 0
                            }
                            if (bufferInfo.size > 0 && muxerStarted) {
                                encoded.position(bufferInfo.offset)
                                encoded.limit(bufferInfo.offset + bufferInfo.size)
                                muxer.writeSampleData(trackIndex, encoded, bufferInfo)
                            }
                            codec.releaseOutputBuffer(outIndex, false)
                            if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
                        }
                    }
                }
            } finally {
                try { codec.stop(); codec.release() } catch (_: Exception) {}
                try { if (muxerStarted) muxer.stop(); muxer.release() } catch (_: Exception) {}
            }
        }
        return File(dstPath).let { it.exists() && it.length() > 0 }
    }

    /** 取樣率與聲道數(標準 44 byte WAV 標頭;本 App 自產的檔案即為此格式)。 */
    private fun parseWavHeader(h: ByteArray): Pair<Int, Int>? {
        if (String(h, 0, 4) != "RIFF" || String(h, 8, 4) != "WAVE") return null
        val channels = (h[22].toInt() and 0xFF) or ((h[23].toInt() and 0xFF) shl 8)
        val sampleRate = (h[24].toInt() and 0xFF) or ((h[25].toInt() and 0xFF) shl 8) or
            ((h[26].toInt() and 0xFF) shl 16) or ((h[27].toInt() and 0xFF) shl 24)
        if (channels <= 0 || sampleRate <= 0) return null
        return sampleRate to channels
    }

    private fun presentationTime(bytesRead: Long, sampleRate: Int, channels: Int): Long {
        val bytesPerSecond = sampleRate.toLong() * channels * 2 // 16-bit
        return bytesRead * 1_000_000L / bytesPerSecond
    }
}
