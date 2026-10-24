import '../providers/service_providers.dart';

/// 「清理錄音檔」的分析結果。
class StorageScan {
  const StorageScan({
    required this.all,
    required this.orphans,
    required this.empty,
  });

  /// 手機上所有錄音 / 匯入檔。
  final List<LocalAudioFile> all;

  /// 在目前帳號的會議清單裡找不到對應會議的檔案(會議多半已刪除)。
  final List<LocalAudioFile> orphans;

  /// 會議還在,但檔案是 0 位元組的壞檔(早期壓縮失敗留下的),沒有任何內容。
  final List<LocalAudioFile> empty;

  int get totalBytes => all.fold(0, (n, f) => n + f.size);

  List<LocalAudioFile> get removable => [...orphans, ...empty];
}

/// 比對手機上的檔案與 server 的會議清單。
///
/// [knownMeetingIds] 必須是**完整**的會議清單(server 的 GET /meetings 沒有
/// 筆數上限);拿不到完整清單時不該呼叫這個函式,否則還在的會議會被誤判。
StorageScan analyzeLocalAudio(
  List<LocalAudioFile> files,
  Set<String> knownMeetingIds,
) {
  final orphans = <LocalAudioFile>[];
  final empty = <LocalAudioFile>[];
  for (final f in files) {
    if (!knownMeetingIds.contains(f.meetingId)) {
      orphans.add(f);
    } else if (f.size == 0) {
      empty.add(f);
    }
  }
  return StorageScan(all: files, orphans: orphans, empty: empty);
}

/// App 錄的 WAV(16kHz、16-bit、單聲道 = 每秒 32,000 位元組)可由大小推算長度,
/// 讓使用者認得出是哪一場。其他格式推算不準,回傳 null。
Duration? estimateRecordingLength(LocalAudioFile f) {
  if (f.imported || !f.file.path.toLowerCase().endsWith('.wav')) return null;
  if (f.size <= 44) return null;
  return Duration(seconds: ((f.size - 44) / 32000).round());
}
