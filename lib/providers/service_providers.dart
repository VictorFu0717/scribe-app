import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/storage/token_storage.dart';
import '../models/transcription_config.dart';
import '../services/audio_player_service.dart';
import '../services/audio_recorder_service.dart';
import '../services/backend.dart';
import '../services/http_backend.dart';
import '../services/mock_backend.dart';
import '../services/speaker_name_store.dart';
import '../services/transcript_edit_store.dart';
import 'settings_controller.dart';

final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());

/// 依設定選擇真後端或 mock。切換 mock / base URL 時會自動重建。
final backendProvider = Provider<Backend>((ref) {
  final settings = ref.watch(settingsProvider);
  final Backend backend;
  if (settings.useMock) {
    backend = MockBackend();
  } else {
    backend = HttpBackend(
      baseUrl: settings.baseUrl,
      tokenStorage: ref.watch(tokenStorageProvider),
    );
  }
  ref.onDispose(backend.dispose);
  return backend;
});

final audioRecorderProvider = Provider<AudioRecorderService>((ref) {
  final r = AudioRecorderService();
  ref.onDispose(r.dispose);
  return r;
});

final audioPlayerProvider = Provider<AudioPlayerService>((ref) {
  final p = AudioPlayerService();
  ref.onDispose(p.dispose);
  return p;
});

/// 由目前設定組出的轉錄設定。
final transcriptionConfigProvider = Provider<TranscriptionConfig>((ref) {
  final s = ref.watch(settingsProvider);
  return TranscriptionConfig(
    diarization: s.diarization,
    speakerCount: s.speakerCount,
  );
});

/// App 目前的 Documents 資料夾(啟動時於 main() 取得後注入)。
///
/// 測試環境沒有 path_provider 的原生端,維持 null —— 此時錄音路徑照原樣使用。
final documentsDirProvider = Provider<String?>((ref) => null);

/// 會議 → 本地錄音檔路徑(供播放)。以 SharedPreferences 持久化。
final localRecordingStoreProvider =
    Provider<LocalRecordingStore>((ref) => LocalRecordingStore(
          ref.read(sharedPreferencesProvider),
          documentsDir: ref.read(documentsDirProvider),
        ));

/// 會議 → 本地錄音檔。
///
/// **只記檔名(相對於 Documents),不記絕對路徑。** iOS 每次安裝/更新 App,
/// 沙盒路徑裡的 UUID 都會換(/var/mobile/Containers/Data/Application/<UUID>/…),
/// 檔案會被搬到新資料夾,但記下的絕對路徑就指向不存在的舊資料夾 —— 實測每次
/// 更新後所有錄音都「消失」,其實 91 個檔案全都還在手機裡。
///
/// 舊版存的絕對路徑仍讀得回來:找不到時改用檔名到目前的 Documents 找,
/// 找到就順手改存成檔名,之後不必再找。
class LocalRecordingStore {
  LocalRecordingStore(this._prefs, {String? documentsDir})
      : _docs = documentsDir;

  final SharedPreferences _prefs;
  final String? _docs;

  String _key(String meetingId) => 'local_audio.$meetingId';

  String? pathFor(String meetingId) {
    final stored = _prefs.getString(_key(meetingId));
    final docs = _docs;
    if (stored == null) return docs == null ? null : _byConvention(meetingId);
    if (docs == null) return stored;

    // 新格式:檔名(相對路徑)
    if (!stored.startsWith('/')) return _playable('$docs/$stored') ?? '$docs/$stored';

    // 舊格式:絕對路徑。還有效就直接用(Android 的路徑不會變)
    final direct = _playable(stored);
    if (direct != null) return direct;

    // 沙盒資料夾換過了:用檔名到目前的 Documents 找
    final name = stored.substring(stored.lastIndexOf('/') + 1);
    final moved = _playable('$docs/$name');
    if (moved != null) {
      // 自我修復:改存成檔名(不 await —— 寫入失敗下次再找一次即可)
      _prefs.setString(_key(meetingId), _relative(moved) ?? moved);
      return moved;
    }
    return stored;
  }

  /// 錄音與匯入檔的檔名本身就含會議 id(rec_<id>.wav、import_<id>.<原副檔名>),
  /// 是 App 自己定的命名規則。沒有記錄時照這個規則找。
  ///
  /// 會有「檔案在、記錄不在」:早期上傳大檔途中會閃退,記錄來不及寫入
  /// (實測手機裡有 6 個這樣的檔案)。找到就補寫記錄。
  static const _audioExts = [
    'wav', 'm4a', 'mp3', 'aac', 'caf', 'mp4', 'ogg', 'flac', 'amr', 'opus',
  ];

  String? _byConvention(String meetingId) {
    final docs = _docs!;
    for (final prefix in const ['rec_', 'import_']) {
      for (final ext in _audioExts) {
        final path = '$docs/$prefix$meetingId.$ext';
        final f = File(path);
        if (f.existsSync() && f.lengthSync() > 0) {
          _prefs.setString(_key(meetingId), '$prefix$meetingId.$ext');
          return path;
        }
      }
    }
    return null;
  }

  /// 檔案存在且有內容就回傳它;否則試同名的另一種格式。
  ///
  /// 早期壓縮功能壞掉時,留下過 0 位元組的 .m4a(原本的 .wav 還在),
  /// 若記錄指向那個空檔,播放器會出現卻放不出聲音。
  String? _playable(String path) {
    final f = File(path);
    if (f.existsSync() && f.lengthSync() > 0) return path;
    final dot = path.lastIndexOf('.');
    if (dot < 0) return null;
    final base = path.substring(0, dot);
    for (final ext in const ['.wav', '.m4a']) {
      final alt = File('$base$ext');
      if (alt.path != path && alt.existsSync() && alt.lengthSync() > 0) {
        return alt.path;
      }
    }
    return null;
  }

  /// 在 Documents 底下就回傳相對路徑(檔名),否則 null。
  String? _relative(String path) {
    final docs = _docs;
    if (docs == null || !path.startsWith('$docs/')) return null;
    return path.substring(docs.length + 1);
  }

  Future<void> save(String meetingId, String path) =>
      _prefs.setString(_key(meetingId), _relative(path) ?? path);

  /// 錄音 / 匯入檔的命名規則:rec_<會議 id>.<副檔名>、import_<會議 id>.<副檔名>。
  static final _fileRe = RegExp(r'^(rec|import)_(.+)\.([A-Za-z0-9]+)$');

  /// Documents 裡所有錄音 / 匯入檔(依檔名辨識所屬會議),新的在前。
  List<LocalAudioFile> allFiles() {
    final docs = _docs;
    if (docs == null) return const [];
    final dir = Directory(docs);
    if (!dir.existsSync()) return const [];
    final out = <LocalAudioFile>[];
    for (final e in dir.listSync(followLinks: false)) {
      if (e is! File) continue;
      final name = e.path.substring(e.path.lastIndexOf(Platform.pathSeparator) + 1);
      final m = _fileRe.firstMatch(name);
      if (m == null) continue;
      try {
        final stat = e.statSync();
        out.add(LocalAudioFile(
          file: e,
          meetingId: m.group(2)!,
          imported: m.group(1) == 'import',
          size: stat.size,
          modified: stat.modified,
        ));
      } catch (_) {
        // 讀不到屬性的檔案略過(可能剛好被刪)
      }
    }
    out.sort((a, b) => b.modified.compareTo(a.modified));
    return out;
  }

  /// 這場會議在手機上的所有檔案:壓縮前後兩種格式、錄到一半留下的 .pcm,
  /// 以及記錄指向 Documents 以外的檔案。
  ///
  /// 會議 id 必須**完全相同**才算 —— rec_abc_x.wav 不屬於會議 abc。
  List<File> filesFor(String meetingId) {
    final files = <String, File>{
      for (final f in allFiles())
        if (f.meetingId == meetingId) f.file.path: f.file,
    };
    final stored = pathFor(meetingId);
    if (stored != null && File(stored).existsSync()) files[stored] = File(stored);
    return files.values.toList();
  }

  /// 只移除記錄,不動檔案(清理時檔案已個別刪除)。
  Future<void> forget(String meetingId) => _prefs.remove(_key(meetingId));

  /// 刪除這場會議在手機上的錄音檔與記錄,回傳刪掉的檔案數。
  Future<int> deleteFor(String meetingId) async {
    var deleted = 0;
    for (final f in filesFor(meetingId)) {
      try {
        await f.delete();
        deleted++;
      } catch (_) {
        // 個別檔案刪不掉不影響其他的;日後可在「清理錄音檔」再處理
      }
    }
    await _prefs.remove(_key(meetingId));
    return deleted;
  }
}

/// 手機上的一個錄音 / 匯入音檔。
class LocalAudioFile {
  const LocalAudioFile({
    required this.file,
    required this.meetingId,
    required this.imported,
    required this.size,
    required this.modified,
  });

  final File file;

  /// 依檔名辨識出的會議 id。
  final String meetingId;

  /// true = 從其他 App 或檔案匯入的音檔(import_ 開頭),false = App 錄的。
  final bool imported;

  final int size;
  final DateTime modified;
}

/// 逐字稿的人工修訂(辨識有誤時自行改正)。以 SharedPreferences 持久化。
final transcriptEditStoreProvider = Provider<TranscriptEditStore>(
    (ref) => TranscriptEditStore(ref.read(sharedPreferencesProvider)));

/// 說話者改名與逐段指派。以 SharedPreferences 持久化。
final speakerNameStoreProvider = Provider<SpeakerNameStore>(
    (ref) => SpeakerNameStore(ref.read(sharedPreferencesProvider)));

/// 每場會議各自的翻譯設定。
final meetingTranslationStoreProvider = Provider<MeetingTranslationStore>(
    (ref) => MeetingTranslationStore(ref.read(sharedPreferencesProvider)));

/// 一場會議的翻譯設定:是否翻譯,以及來源 → 目標語言。
class MeetingTranslationPref {
  const MeetingTranslationPref({
    required this.enabled,
    required this.source,
    required this.target,
  });

  final bool enabled;
  final String source;
  final String target;

  MeetingTranslationPref copyWith({
    bool? enabled,
    String? source,
    String? target,
  }) =>
      MeetingTranslationPref(
        enabled: enabled ?? this.enabled,
        source: source ?? this.source,
        target: target ?? this.target,
      );
}

/// 記錄每場會議自己的翻譯設定(以 meetingId 為 key)。
///
/// 為什麼是「每場」而非全域:多數會議不需要翻譯,只有少數要;而且各場語言不同 ——
/// 拿當下的全域方向去翻所有會議,英文會議套上「中文→英文」時 ML Kit 會把英文
/// 當中文而原樣吐回(看起來像「英文翻英文」)。全域設定僅作為新錄音的預設值。
class MeetingTranslationStore {
  MeetingTranslationStore(this._prefs);
  final SharedPreferences _prefs;

  String _key(String meetingId) => 'meeting_translation.$meetingId';

  /// 尚未設定過的會議回 null(呼叫端據此套用預設:不翻譯)。
  MeetingTranslationPref? prefFor(String meetingId) {
    final raw = _prefs.getString(_key(meetingId));
    if (raw == null) return null;
    final parts = raw.split('|'); // 格式:enabled|source|target
    if (parts.length != 3 || parts[1].isEmpty || parts[2].isEmpty) return null;
    return MeetingTranslationPref(
      enabled: parts[0] == '1',
      source: parts[1],
      target: parts[2],
    );
  }

  Future<void> clear(String meetingId) => _prefs.remove(_key(meetingId));

  Future<void> save(String meetingId, MeetingTranslationPref pref) =>
      _prefs.setString(_key(meetingId),
          '${pref.enabled ? 1 : 0}|${pref.source}|${pref.target}');
}
