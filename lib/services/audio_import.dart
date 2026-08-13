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

  final store = ref.read(localRecordingStoreProvider);

  // 1) 先把檔案複製到本機 —— iOS 選檔回傳的是 security-scoped 路徑,
  //    上傳大檔耗時數分鐘後可能已失去存取權。
  final localCopy = await _copyToDocuments(path, meeting.id);

  // 2) 複製完**立刻**記錄路徑,不等上傳與壓縮。
  //    先前把 save 放在最後,結果 App 在上傳途中被 iOS 因記憶體壓力終止,
  //    save 從未執行 → 逐字稿有了卻沒有播放器(實測兩次皆如此)。
  if (localCopy != null) {
    await store.save(meeting.id, localCopy);
  }

  // 3) 上傳**未壓縮原檔**,辨識品質優先。
  //    先前為了避免上傳中斷而改成壓縮後上傳,但後來確認那些中斷的真因是壓縮本身
  //    會崩潰(見 AudioConvert),而非上傳量 —— 使用者實測「重新轉錄」上傳同樣的
  //    110MB 原檔是可以成功的。
  await backend.uploadAudio(meeting.id, localCopy ?? path, config: config);

  // 4) 上傳完成後才壓縮本機副本(一小時 110MB → 約 8MB),省空間並便於分享。
  //    失敗也無妨:記錄仍指向原檔,播放與分享照常。
  if (localCopy != null && await AudioConvert.isWav(localCopy)) {
    final compressed = await AudioConvert.wavToM4a(localCopy);
    if (compressed != null) {
      await store.save(meeting.id, compressed);
    }
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
