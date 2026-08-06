import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:audio_session/audio_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_exception.dart';
import '../models/transcript_segment.dart';
import '../services/audio_session_config.dart';
import '../services/keep_awake.dart';
import '../services/on_device_translator.dart';
import '../services/backend.dart';
import '../services/recording_foreground_service.dart';
import 'meetings_controller.dart';
import 'service_providers.dart';
import 'settings_controller.dart';

enum RecordingPhase { idle, starting, recording, paused, finalizing, error }

/// 即時(裝置內)翻譯的狀態,顯示給使用者以便知道卡在哪。
enum TranslationStatus {
  /// 未開啟翻譯。
  off,

  /// 正在準備(首次使用某語言需下載模型,約 30MB)。
  preparing,

  /// 可翻譯。
  ready,

  /// 不可用(模型下載失敗、語言不支援或來源=目標)。
  unavailable,
}

class RecordingState {
  const RecordingState({
    this.phase = RecordingPhase.idle,
    this.meetingId,
    this.title = '',
    this.finalSegments = const [],
    this.partial,
    this.elapsed = Duration.zero,
    this.level = 0,
    this.error,
    this.translations = const {},
    this.translationStatus = TranslationStatus.off,
    this.interrupted = false,
  });

  final RecordingPhase phase;
  final String? meetingId;
  final String title;

  /// 已定稿(VAD 分段)的逐字稿。
  final List<TranscriptSegment> finalSegments;

  /// 暫定片段(邊錄邊出,尚未定稿)。
  final TranscriptSegment? partial;

  final Duration elapsed;

  /// 目前音量 0..1(用於視覺回饋)。
  final double level;
  final String? error;

  /// 定稿片段的譯文(key = 片段 id)。翻譯關閉、尚未譯出或翻譯失敗則無該鍵。
  /// 由裝置內翻譯即時產生(見 [OnDeviceTranslatorService]),不打 server。
  final Map<String, String> translations;

  /// 即時翻譯的準備狀態(讓 UI 能顯示「下載模型中」或「不可用」而非靜默無譯文)。
  final TranslationStatus translationStatus;

  /// 音訊正被中斷(來電、鬧鐘、其他 App 搶音訊)。中斷結束會自動恢復錄音。
  final bool interrupted;

  bool get isActive =>
      phase == RecordingPhase.recording || phase == RecordingPhase.paused;

  RecordingState copyWith({
    RecordingPhase? phase,
    String? meetingId,
    String? title,
    List<TranscriptSegment>? finalSegments,
    TranscriptSegment? partial,
    bool clearPartial = false,
    Duration? elapsed,
    double? level,
    String? error,
    bool clearError = false,
    Map<String, String>? translations,
    TranslationStatus? translationStatus,
    bool? interrupted,
  }) {
    return RecordingState(
      phase: phase ?? this.phase,
      meetingId: meetingId ?? this.meetingId,
      title: title ?? this.title,
      finalSegments: finalSegments ?? this.finalSegments,
      partial: clearPartial ? null : (partial ?? this.partial),
      elapsed: elapsed ?? this.elapsed,
      level: level ?? this.level,
      error: clearError ? null : (error ?? this.error),
      translations: translations ?? this.translations,
      translationStatus: translationStatus ?? this.translationStatus,
      interrupted: interrupted ?? this.interrupted,
    );
  }
}

final recordingControllerProvider =
    NotifierProvider<RecordingController, RecordingState>(
        RecordingController.new);

class RecordingController extends Notifier<RecordingState> {
  TranscriptionSession? _session;
  StreamSubscription<TranscriptUpdate>? _segSub;
  StreamSubscription<Uint8List>? _audioSub;
  StreamSubscription<AudioInterruptionEvent>? _interruptSub;
  Timer? _timer;

  /// 裝置內即時翻譯(雙語字幕);翻譯關閉或模型未就緒時 [_translationReady] 為 false。
  final OnDeviceTranslatorService _translator = OnDeviceTranslatorService();
  bool _translationReady = false;

  /// 已翻譯過的原文(key = 片段 id)。server 會就地升級定稿文字,
  /// 文字變了就得重譯,故記錄「翻譯當時的原文」而非只記已翻過。
  final Map<String, String> _translatedSource = {};
  bool _translating = false;

  @override
  RecordingState build() {
    ref.onDispose(_teardown);
    return const RecordingState();
  }

  /// 開始一場新錄音。回傳建立的 meetingId(失敗回 null)。
  Future<String?> start({required String title}) async {
    if (state.isActive) return state.meetingId;
    final backend = ref.read(backendProvider);
    final recorder = ref.read(audioRecorderProvider);
    final config = ref.read(transcriptionConfigProvider);

    state = RecordingState(phase: RecordingPhase.starting, title: title);

    try {
      if (!await recorder.hasPermission()) {
        state = state.copyWith(
            phase: RecordingPhase.error, error: '沒有麥克風權限,請到系統設定開啟。');
        return null;
      }

      // 切到錄音用 audio session(playAndRecord)。
      await AudioSessions.recording();

      // 錄音時螢幕常亮(避免自動鎖屏 → App 被 iOS 暫停中斷背景錄音)。
      if (ref.read(settingsProvider).keepScreenOn) {
        await KeepAwake.enable();
      }

      // 音訊中斷(來電/通知/其他 App 搶音訊)結束後自動續錄。
      await _listenInterruptions();

      // 裝置內翻譯(雙語字幕)。首次使用某語言會下載模型,故不阻斷錄音啟動:
      // 準備失敗就單純不顯示譯文。
      final settings = ref.read(settingsProvider);
      _translationReady = false;
      _translatedSource.clear();
      if (settings.translationEnabled) {
        state = state.copyWith(translationStatus: TranslationStatus.preparing);
        _translator
            .prepare(settings.translationSource, settings.translationTarget)
            .then((ok) {
          _translationReady = ok;
          state = state.copyWith(
              translationStatus:
                  ok ? TranslationStatus.ready : TranslationStatus.unavailable);
          if (ok) _translatePending();
        });
      }

      // Android:啟動麥克風型前景服務,讓鎖屏/背景能持續錄音(iOS 為 no-op)。
      await RecordingForegroundService.start(title: title);

      final meeting = await backend.createMeeting(title: title);

      // 開 WS 連線並訂閱即時逐字稿(手機錄音一律即時串流)。
      {
        final session = backend.openTranscription(
          meetingId: meeting.id,
          config: config,
        );
        _session = session;
        _segSub = session.updates.listen(
          _onUpdate,
          onError: (e) => state = state.copyWith(
              error: e is ApiException ? e.message : '轉錄連線中斷'),
        );
      }

      final pcmStream = await recorder.start(meetingId: meeting.id);
      _listenAudio(pcmStream);

      _startTimer();
      state = state.copyWith(
        phase: RecordingPhase.recording,
        meetingId: meeting.id,
        clearError: true,
      );
      return meeting.id;
    } catch (e) {
      await _teardown();
      state = state.copyWith(
          phase: RecordingPhase.error,
          error: e is ApiException ? e.message : '無法開始錄音:$e');
      return null;
    }
  }

  Future<void> pauseResume() async {
    final recorder = ref.read(audioRecorderProvider);
    if (state.phase == RecordingPhase.recording) {
      await recorder.pause();
      _timer?.cancel();
      state = state.copyWith(phase: RecordingPhase.paused, level: 0);
    } else if (state.phase == RecordingPhase.paused) {
      await recorder.resume();
      _startTimer();
      state = state.copyWith(phase: RecordingPhase.recording);
    }
  }

  /// 停止錄音並收尾。回傳 meetingId。
  Future<String?> stop() async {
    if (!state.isActive) return state.meetingId;
    final meetingId = state.meetingId;
    state = state.copyWith(phase: RecordingPhase.finalizing);
    _timer?.cancel();

    final recorder = ref.read(audioRecorderProvider);

    // 關閉背景保活(wakelock / 中斷監聽)與前景服務。
    await _releaseKeepAlive();
    await RecordingForegroundService.stop();

    String? wavPath;
    try {
      wavPath = await recorder.stop();
    } catch (_) {}
    await _audioSub?.cancel();
    _audioSub = null;

    // 通知 server 收尾(即時串流)。
    await _session?.stop();
    await _segSub?.cancel();
    _segSub = null;
    _session = null;

    // 本地保存錄音檔(供播放/防斷線)。
    if (meetingId != null && wavPath != null) {
      await ref.read(localRecordingStoreProvider).save(meetingId, wavPath);
    }

    // 記住這場會議的翻譯設定(是否翻譯 + 方向)。全域設定之後可能改成別的方向,
    // 但這場的逐字稿語言已經固定;不記的話,日後重看會用當下設定去翻而語言不符
    // (例如英文會議套上「中文→英文」,ML Kit 會原樣吐回英文)。
    if (meetingId != null) {
      final s = ref.read(settingsProvider);
      await ref.read(meetingTranslationStoreProvider).save(
            meetingId,
            MeetingTranslationPref(
              enabled: s.translationEnabled,
              source: s.translationSource,
              target: s.translationTarget,
            ),
          );
    }

    ref.invalidate(meetingsListProvider);
    state = const RecordingState();
    return meetingId;
  }

  /// 累積式快照:直接替換整份逐字稿(天然支援 server 的「就地升級」)。
  void _onUpdate(TranscriptUpdate u) {
    state = state.copyWith(
      finalSegments: u.finalSegments,
      partial: u.partial,
      clearPartial: u.partial == null,
    );
    if (_translationReady) _translatePending();
  }

  /// 依序翻譯尚未翻譯(或原文被 server 升級過)的定稿片段。
  /// 一次只跑一輪,避免快照頻繁更新造成重複翻譯。
  Future<void> _translatePending() async {
    if (_translating || !_translationReady) return;
    _translating = true;
    try {
      // 逐句翻;每句翻完就更新 state,讓譯文陸續出現而非等全部。
      while (true) {
        TranscriptSegment? pending;
        for (final s in state.finalSegments) {
          if (s.text.trim().isNotEmpty && _translatedSource[s.id] != s.text) {
            pending = s;
            break;
          }
        }
        if (pending == null) break;

        final source = pending.text;
        final translated = await _translator.translate(source);
        // 記錄「已處理過這份原文」——失敗也記,避免同一句無限重試。
        _translatedSource[pending.id] = source;
        if (translated == null) continue;
        state = state.copyWith(translations: {
          ...state.translations,
          pending.id: translated,
        });
      }
    } finally {
      _translating = false;
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      state = state.copyWith(elapsed: state.elapsed + const Duration(seconds: 1));
    });
  }

  /// 訂閱 PCM 串流:送去 server 轉錄並更新音量。中斷恢復後會重新訂閱新串流。
  void _listenAudio(Stream<Uint8List> pcmStream) {
    _audioSub = pcmStream.listen((chunk) {
      _session?.sendAudio(chunk);
      final lvl = _computeLevel(chunk);
      if ((lvl - state.level).abs() > 0.02) {
        state = state.copyWith(level: lvl);
      }
    });
  }

  /// 監聽音訊中斷(來電、鬧鐘、其他 App 搶音訊)並在結束後自動恢復。
  Future<void> _listenInterruptions() async {
    try {
      final session = await AudioSession.instance;
      _interruptSub = session.interruptionEventStream.listen((event) async {
        if (state.phase != RecordingPhase.recording) return;
        if (event.begin) {
          // 中斷開始:iOS 已切斷我們的麥克風輸入,標記狀態讓 UI 說明現況。
          state = state.copyWith(interrupted: true);
          return;
        }
        await _resumeAfterInterruption();
      });
    } catch (_) {}
  }

  /// 中斷結束後恢復錄音。
  ///
  /// 關鍵:串流模式下不能用 `resume()` —— 中斷會讓原本那條 PCM Stream 結束,
  /// 即使 recorder 恢復也不會再有資料進來(先前就是這樣「看起來還在錄、實際已停」)。
  /// 必須重新 startStream 並重新訂閱;PCM 續寫同一檔案,錄音檔不斷裂。
  Future<void> _resumeAfterInterruption() async {
    if (state.phase != RecordingPhase.recording) return;
    try {
      await AudioSessions.recording();
      final recorder = ref.read(audioRecorderProvider);
      await _audioSub?.cancel();
      _audioSub = null;
      final stream = await recorder.restartStream();
      _listenAudio(stream);
      state = state.copyWith(interrupted: false, clearError: true);
    } catch (e) {
      // 恢復失敗要讓使用者知道,不能靜默停止錄音。
      state = state.copyWith(
        interrupted: false,
        error: '錄音被中斷後無法自動恢復,請按停止結束這段,再重新開始錄音。',
      );
    }
  }

  /// 停止背景保活資源(wakelock / 中斷監聽)。
  Future<void> _releaseKeepAlive() async {
    await _interruptSub?.cancel();
    _interruptSub = null;
    await KeepAwake.disable();
    _translationReady = false;
    _translatedSource.clear();
    await _translator.dispose();
  }

  Future<void> _teardown() async {
    _timer?.cancel();
    await _releaseKeepAlive();
    await RecordingForegroundService.stop();
    await _audioSub?.cancel();
    await _segSub?.cancel();
    try {
      await _session?.stop();
    } catch (_) {}
    try {
      await ref.read(audioRecorderProvider).stop();
    } catch (_) {}
    _audioSub = null;
    _segSub = null;
    _session = null;
  }

  static double _computeLevel(Uint8List bytes) {
    if (bytes.length < 2) return 0;
    final bd = ByteData.sublistView(bytes);
    final n = bytes.length ~/ 2;
    double sum = 0;
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      final s = bd.getInt16(i, Endian.little).toDouble();
      sum += s * s;
    }
    final rms = sqrt(sum / n) / 32768.0;
    return (rms * 4).clamp(0.0, 1.0);
  }
}
