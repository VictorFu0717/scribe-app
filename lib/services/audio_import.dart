import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../providers/meetings_controller.dart';
import '../providers/service_providers.dart';
import 'audio_convert.dart';
import 'background_task.dart';

/// 匯入一個既有音檔:建立會議 → 上傳給 server 背景轉錄 → 回傳 meetingId。
///
/// 由兩處共用:會議清單的「上傳音檔」按鈕,以及從其他 App 分享進來的音檔
/// (見 [IncomingFile])。失敗時丟出例外,由呼叫端顯示訊息。
///
/// 取 WidgetRef 而非 Ref:兩個呼叫端都在 widget 內(清單頁與 HomeShell)。
Future<String> importAudioFile(WidgetRef ref, String path) =>
    // 整段包在 background task 內:上傳大檔可能數分鐘,期間 App 若離開前景
    // 會被 iOS 暫停,上傳就中斷(實測一小時的檔案上傳到一半即中止)。
    BackgroundTask.run(() => _importAudioFile(ref, path));

Future<String> _importAudioFile(WidgetRef ref, String path) async {
  final backend = ref.read(backendProvider);
  final config = ref.read(transcriptionConfigProvider);

  final meeting = await backend.createMeeting(title: titleFromPath(path));

  // **先**把檔案複製到本機再上傳。
  //
  // 順序很重要:iOS 選檔回傳的是 security-scoped 路徑,上傳(耗時,大檔可達數分鐘)
  // 之後可能已失去存取權 —— 先前把複製放在上傳後,結果一小時的檔案上傳完卻留不下
  // 本機副本,會議詳情因此沒有播放器(實測)。Android 的 SAF 檔案位於 App 快取,
  // 也可能被系統清除。server 端不留存上傳的音檔,要能回聽就得靠本機這一份。
  final localCopy = await _copyToDocuments(path, meeting.id);

  // 上傳用原始格式(未壓縮),避免影響辨識準確度。
  await backend.uploadAudio(meeting.id, localCopy ?? path, config: config);

  if (localCopy != null) {
    // 上傳完成後才壓縮本機副本(WAV 一小時約 110MB,壓成 m4a 約 28MB)。
    final compressed = localCopy.toLowerCase().endsWith('.wav')
        ? await AudioConvert.wavToM4a(localCopy)
        : null;
    await ref
        .read(localRecordingStoreProvider)
        .save(meeting.id, compressed ?? localCopy);
  }

  ref.invalidate(meetingsListProvider);
  return meeting.id;
}

/// 把音檔複製到 App 的永久目錄(與手機錄音同一處),回傳新路徑;失敗回 null。
///
/// 只複製、不轉檔 —— 轉檔要等上傳完成後才做,以免上傳到壓縮過的音訊而影響辨識。
Future<String?> _copyToDocuments(String srcPath, String meetingId) async {
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
