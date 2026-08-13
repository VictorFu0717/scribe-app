package com.netchinese.meeting_assistant

import android.app.Activity
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

    /// SAF「另存新檔」進行中的狀態:對話框是非同步的,結果要在 onActivityResult 才拿到。
    /// Android 的分享選單沒有「儲存到檔案」,存到手機必須走 ACTION_CREATE_DOCUMENT。
    private var pendingSaveResult: MethodChannel.Result? = null
    private var pendingSaveSrc: String? = null

    /// SAF「開啟文件」進行中的狀態(選音檔上傳用)。
    private var pendingPickResult: MethodChannel.Result? = null

    companion object {
        private const val REQ_CREATE_DOCUMENT = 4711
        private const val REQ_OPEN_DOCUMENT = 4712
    }

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

        // WAV → m4a(AAC 64kbps):一小時 WAV 約 110MB,轉檔後約 28MB,才傳得出去。
        // 見 lib/services/audio_convert.dart。
        MethodChannel(messenger, "app/audio_convert")
            .setMethodCallHandler { call, result ->
                if (call.method == "wavToM4a") {
                    val src = call.argument<String>("src")
                    val dst = call.argument<String>("dst")
                    val bitRate = call.argument<Int>("bitRate") ?: 48_000
                    if (src == null || dst == null) {
                        result.success(false)
                    } else {
                        // 編碼是耗時工作,不可佔用主執行緒。
                        Thread {
                            val ok = try {
                                WavToAac.convert(src, dst, bitRate)
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

        // 存到手機(SAF 另存新檔)。iOS 不需要 —— 其分享面板已內建「儲存到檔案」。
        // 見 lib/services/save_to_device.dart。
        MethodChannel(messenger, "app/save_file")
            .setMethodCallHandler { call, result ->
                if (call.method == "save") {
                    val src = call.argument<String>("src")
                    val name = call.argument<String>("name") ?: "recording.m4a"
                    val mime = call.argument<String>("mime") ?: "audio/mp4"
                    if (src == null || !File(src).exists()) {
                        result.success(false)
                    } else if (pendingSaveResult != null) {
                        result.success(false) // 已有對話框進行中
                    } else {
                        pendingSaveResult = result
                        pendingSaveSrc = src
                        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = mime
                            putExtra(Intent.EXTRA_TITLE, name)
                        }
                        try {
                            startActivityForResult(intent, REQ_CREATE_DOCUMENT)
                        } catch (e: Exception) {
                            pendingSaveResult = null
                            pendingSaveSrc = null
                            result.success(false)
                        }
                    }
                } else {
                    result.notImplemented()
                }
            }

        // 選取既有音檔(SAF)。不用 file_selector_android —— 它會把整個檔案讀成
        // bytes 經 channel 傳回 Dart,選上百 MB 的錄音檔會 OOM 閃退。
        // 這裡串流複製到快取,只回傳路徑。見 lib/services/audio_file_picker.dart。
        MethodChannel(messenger, "app/pick_audio")
            .setMethodCallHandler { call, result ->
                if (call.method == "pick") {
                    if (pendingPickResult != null) {
                        result.success(null) // 已有選取器開著
                    } else {
                        pendingPickResult = result
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "audio/*"
                        }
                        try {
                            startActivityForResult(intent, REQ_OPEN_DOCUMENT)
                        } catch (e: Exception) {
                            pendingPickResult = null
                            result.success(null)
                        }
                    }
                } else {
                    result.notImplemented()
                }
            }

        // 冷啟動:啟動本 Activity 的 intent 可能就帶著分享的檔案。
        handleIncomingIntent(intent)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            REQ_CREATE_DOCUMENT -> handleSaveResult(resultCode, data)
            REQ_OPEN_DOCUMENT -> handlePickResult(resultCode, data)
        }
    }

    /// SAF 選檔結果:串流複製到快取後回傳路徑(不把檔案讀進記憶體)。
    private fun handlePickResult(resultCode: Int, data: Intent?) {
        val result = pendingPickResult ?: return
        pendingPickResult = null

        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null) // 使用者取消
            return
        }
        // 大檔複製較久,不佔用主執行緒。
        Thread {
            val path = try {
                copyToCache(uri)
            } catch (e: Exception) {
                null
            }
            runOnUiThread { result.success(path) }
        }.start()
    }

    /// SAF 另存新檔的結果:把來源檔內容寫進使用者選定的位置。
    private fun handleSaveResult(resultCode: Int, data: Intent?) {
        val result = pendingSaveResult
        val src = pendingSaveSrc
        pendingSaveResult = null
        pendingSaveSrc = null
        if (result == null) return

        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null || src == null) {
            result.success(false) // 使用者取消
            return
        }
        // 寫檔可能較久(錄音檔可達數十 MB),不佔用主執行緒。
        Thread {
            val ok = try {
                contentResolver.openOutputStream(uri)?.use { output ->
                    File(src).inputStream().use { input -> input.copyTo(output) }
                } != null
            } catch (e: Exception) {
                false
            }
            runOnUiThread { result.success(ok) }
        }.start()
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
