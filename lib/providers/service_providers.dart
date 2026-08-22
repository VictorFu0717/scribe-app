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

/// 會議 → 本地錄音檔路徑(供播放)。以 SharedPreferences 持久化。
final localRecordingStoreProvider =
    Provider<LocalRecordingStore>((ref) => LocalRecordingStore(
          ref.read(sharedPreferencesProvider),
        ));

class LocalRecordingStore {
  LocalRecordingStore(this._prefs);
  final SharedPreferences _prefs;

  String _key(String meetingId) => 'local_audio.$meetingId';

  String? pathFor(String meetingId) => _prefs.getString(_key(meetingId));

  Future<void> save(String meetingId, String path) =>
      _prefs.setString(_key(meetingId), path);
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

  Future<void> save(String meetingId, MeetingTranslationPref pref) =>
      _prefs.setString(_key(meetingId),
          '${pref.enabled ? 1 : 0}|${pref.source}|${pref.target}');
}
