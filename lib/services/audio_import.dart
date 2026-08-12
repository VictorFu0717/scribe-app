import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../providers/meetings_controller.dart';
import '../providers/service_providers.dart';
import 'audio_convert.dart';

/// 匯入一個既有音檔:建立會議 → 上傳給 server 背景轉錄 → 回傳 meetingId。
///
/// 由兩處共用:會議清單的「上傳音檔」按鈕,以及從其他 App 分享進來的音檔
/// (見 [IncomingFile])。失敗時丟出例外,由呼叫端顯示訊息。
///
/// 取 WidgetRef 而非 Ref:兩個呼叫端都在 widget 內(清單頁與 HomeShell)。
Future<String> importAudioFile(WidgetRef ref, String path) async {
  final backend = ref.read(backendProvider);
  final config = ref.read(transcriptionConfigProvider);

  final meeting = await backend.createMeeting(title: titleFromPath(path));
  await backend.uploadAudio(meeting.id, path, config: config);

  // 在本機留一份,讓這場會議之後也能播放、能點逐字稿的時間戳跳回原音對照。
  //
  // 為什麼要複製而不直接記原路徑:選檔來源的路徑不可靠 —— Android 的 SAF 檔案是
  // 複製到 App **快取**(可能被系統清除),iOS 的選檔路徑常位於 tmp/Inbox。
  // server 端不留存上傳的音檔(轉錄完即丟),所以要播就得靠本機這一份。
  final kept = await _keepLocalCopy(path, meeting.id);
  if (kept != null) {
    await ref.read(localRecordingStoreProvider).save(meeting.id, kept);
  }

  ref.invalidate(meetingsListProvider);
  return meeting.id;
}

/// 把音檔複製到 App 的永久目錄(與手機錄音同一處),回傳新路徑;失敗回 null。
///
/// 若來源是未壓縮的 WAV 會轉成 m4a —— 一小時的 WAV 約 110MB,留原檔太佔空間。
Future<String?> _keepLocalCopy(String srcPath, String meetingId) async {
  try {
    final src = File(srcPath);
    if (!src.existsSync()) return null;

    final dir = await getApplicationDocumentsDirectory();
    final ext = srcPath.contains('.')
        ? srcPath.substring(srcPath.lastIndexOf('.') + 1).toLowerCase()
        : 'm4a';
    final dst = '${dir.path}/import_$meetingId.$ext';

    // 串流複製,避免把整個檔案讀進記憶體(可能上百 MB)。
    await src.openRead().pipe(File(dst).openWrite());

    if (ext == 'wav') {
      final compressed = await AudioConvert.wavToM4a(dst);
      if (compressed != null) return compressed;
    }
    return dst;
  } catch (_) {
    return null; // 留不下來不影響轉錄結果,只是之後無法在 App 內播放
  }
}

/// 以檔名(去副檔名)當會議標題;取不到時給預設值。
String titleFromPath(String path) {
  final name = path.split(Platform.pathSeparator).last;
  final dot = name.lastIndexOf('.');
  final base = (dot > 0 ? name.substring(0, dot) : name).trim();
  return base.isEmpty ? '匯入的錄音' : base;
}
