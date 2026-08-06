import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/storage/token_storage.dart';
import '../models/transcription_config.dart';
import '../services/audio_player_service.dart';
import '../services/audio_recorder_service.dart';
import '../services/backend.dart';
import '../services/http_backend.dart';
import '../services/mock_backend.dart';
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

/// 每場會議「錄音當下」的翻譯方向。
final meetingTranslationDirectionStoreProvider =
    Provider<MeetingTranslationDirectionStore>(
        (ref) => MeetingTranslationDirectionStore(
              ref.read(sharedPreferencesProvider),
            ));

/// 一場會議的翻譯方向(來源語言 → 目標語言)。
class TranslationDirection {
  const TranslationDirection(this.source, this.target);
  final String source;
  final String target;

  TranslationDirection get reversed => TranslationDirection(target, source);

  @override
  String toString() => '$source>$target';
}

/// 記錄每場會議該用的翻譯方向。
///
/// 為什麼需要:翻譯方向是**全域設定**,但每場會議的語言不同 —— 有的中文會議、
/// 有的英文會議。若一律用當下的全域設定去翻,英文會議套上「中文→英文」時,
/// ML Kit 會把英文當中文處理而原樣吐回,看起來就是「英文翻英文」;
/// 中文會議套上「英文→中文」則譯文變中文。故改為記住錄音當下的方向。
class MeetingTranslationDirectionStore {
  MeetingTranslationDirectionStore(this._prefs);
  final SharedPreferences _prefs;

  String _key(String meetingId) => 'translation_dir.$meetingId';

  TranslationDirection? directionFor(String meetingId) {
    final raw = _prefs.getString(_key(meetingId));
    if (raw == null) return null;
    final parts = raw.split('>');
    if (parts.length != 2 || parts[0].isEmpty || parts[1].isEmpty) return null;
    return TranslationDirection(parts[0], parts[1]);
  }

  Future<void> save(String meetingId, TranslationDirection dir) =>
      _prefs.setString(_key(meetingId), '${dir.source}>${dir.target}');
}
