import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/service_providers.dart';

/// `ref.read` 的型別。Notifier 的 Ref 與 Widget 的 WidgetRef 沒有共同型別,
/// 但兩者的 read 長得一樣,收這個兩邊都能呼叫。
typedef Reader = T Function<T>(ProviderListenable<T> provider);

/// 清掉一場會議留在手機上的所有資料:錄音檔、逐字稿修訂、說話者設定、翻譯設定。
///
/// 只在 server 已經刪除成功之後呼叫 —— server 刪失敗時要保留錄音,免得 server
/// 上的會議還在、錄音卻沒了。每一步各自獨立,任一步失敗都不影響其他步驟
/// (留下的檔案之後可以在「清理錄音檔」處理)。
Future<void> purgeLocalMeetingData(Reader read, String meetingId) async {
  // 正在播這場的錄音就先停掉,檔案才不會刪到一半還被播放器開著。
  try {
    final player = read(audioPlayerProvider);
    if (player.loadedMeetingId == meetingId) await player.stop();
  } catch (_) {}
  try {
    await read(localRecordingStoreProvider).deleteFor(meetingId);
  } catch (_) {}
  try {
    await read(transcriptEditStoreProvider).clearAll(meetingId);
  } catch (_) {}
  try {
    await read(speakerNameStoreProvider).clear(meetingId);
  } catch (_) {}
  try {
    await read(meetingTranslationStoreProvider).clear(meetingId);
  } catch (_) {}
}

/// 只清掉這場會議的本機記錄(錄音路徑、修訂、說話者、翻譯設定),不動檔案。
///
/// 給「清理錄音檔」用:使用者可能只勾選了部分檔案,檔案由畫面個別刪除,
/// 等這場會議的檔案都刪光了,再用這個把殘留的記錄清乾淨。
Future<void> forgetLocalMeetingRecords(Reader read, String meetingId) async {
  for (final step in <Future<void> Function()>[
    () => read(localRecordingStoreProvider).forget(meetingId),
    () => read(transcriptEditStoreProvider).clearAll(meetingId),
    () => read(speakerNameStoreProvider).clear(meetingId),
    () => read(meetingTranslationStoreProvider).clear(meetingId),
  ]) {
    try {
      await step();
    } catch (_) {}
  }
}
