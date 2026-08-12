package com.netchinese.meeting_assistant

import android.content.Intent
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import android.net.Uri
import android.provider.OpenableColumns
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.nio.ByteBuffer

class MainActivity : FlutterActivity() {
    /// 從其他 App 分享/開啟進來、等待 Dart 端取走的音檔路徑。
    /// 冷啟動時 Flutter 尚未就緒,故先暫存,由 Dart 主動來取
    /// (見 lib/services/incoming_file.dart)。
    private var pendingIncomingFile: String? = null

    /// 保留 channel 以便收到檔案時主動通知 Dart(僅作觸發訊號)。
    private var incomingFileChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // 螢幕常亮(錄音期間)。見 lib/services/keep_awake.dart:自行實作以取代 wakelock_plus。
        MethodChannel(messenger, "app/keep_awake")
            .setMethodCallHandler { call, result ->
                if (call.method == "setKeepAwake") {
                    val enable = call.argument<Boolean>("enable") ?: false
                    if (enable) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }

        // 分享進來的音檔:Dart 端於啟動、回到前景,或收到下方通知時來取。
        incomingFileChannel = MethodChannel(messenger, "app/incoming_file").apply {
            setMethodCallHandler { call, result ->
                if (call.method == "take") {
                    result.success(pendingIncomingFile)
                    pendingIncomingFile = null // 取走即清空,避免重複匯入同一檔
                } else {
                    result.notImplemented()
                }
            }
        }

        // WAV → m4a(AAC):一小時 WAV 約 110MB,轉檔後約 9MB,才傳得出去。
        // 見 lib/services/audio_convert.dart。
        MethodChannel(messenger, "app/audio_convert")
            .setMethodCallHandler { call, result ->
                if (call.method == "wavToM4a") {
                    val src = call.argument<String>("src")
                    val dst = call.argument<String>("dst")
                    if (src == null || dst == null) {
                        result.success(false)
                    } else {
                        // 編碼是耗時工作,不可佔用主執行緒。
                        Thread {
                            val ok = try {
                                WavToAac.convert(src, dst)
                            } catch (e: Exception) {
                                false
                            }
                            runOnUiThread { result.success(ok) }
                        }.start()
                    }
                } else {
                    result.notImplemented()
                }
            }

        // 冷啟動:啟動本 Activity 的 intent 可能就帶著分享的檔案。
        handleIncomingIntent(intent)
    }

    /// App 已在執行時再分享一個檔案(launchMode=singleTop 會走這裡)。
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIncomingIntent(intent)
    }

    private fun handleIncomingIntent(intent: Intent?) {
        if (intent == null) return
        val uri: Uri? = when (intent.action) {
            Intent.ACTION_SEND -> intent.getParcelableExtra(Intent.EXTRA_STREAM)
            Intent.ACTION_VIEW -> intent.data
            else -> null
        }
        if (uri != null) {
            copyToCache(uri)?.let {
                pendingIncomingFile = it
                // 主動通知 Dart(僅作觸發訊號,路徑仍由 take 取走以免重複匯入)。
                // 冷啟動時 channel 尚未建立,那種情況由 Dart 啟動後主動來取。
                incomingFileChannel?.invokeMethod("onIncomingFile", null)
            }
        }
    }

    /// 把來源檔複製到 App 快取。
    ///
    /// 必須複製:content:// 的讀取權限綁在這個 intent 上,是一次性的;
    /// 直接保留 URI 之後會讀不到。
    private fun copyToCache(uri: Uri): String? {
        return try {
            val name = displayName(uri) ?: "shared_audio"
            val dir = File(cacheDir, "incoming").apply { mkdirs() }
            var dest = File(dir, name)
            if (dest.exists()) {
                val stamp = System.currentTimeMillis()
                val base = name.substringBeforeLast('.', name)
                val ext = name.substringAfterLast('.', "")
                dest = File(dir, if (ext.isEmpty()) "${base}_$stamp" else "${base}_$stamp.$ext")
            }
            contentResolver.openInputStream(uri)?.use { input ->
                dest.outputStream().use { output -> input.copyTo(output) }
            } ?: return null
            dest.absolutePath
        } catch (e: Exception) {
            null
        }
    }

    /// 取原始檔名(會用來當會議標題)。
    private fun displayName(uri: Uri): String? {
        contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (idx >= 0 && cursor.moveToFirst()) return cursor.getString(idx)
        }
        return uri.lastPathSegment?.substringAfterLast('/')
    }
}
