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
