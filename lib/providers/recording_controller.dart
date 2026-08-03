import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_exception.dart';
import '../models/transcript_segment.dart';
import '../services/audio_session_config.dart';
import '../services/backend.dart';
import '../services/recording_foreground_service.dart';
import 'meetings_controller.dart';
import 'service_providers.dart';

enum RecordingPhase { idle, starting, recording, paused, finalizing, error }

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
  Timer? _timer;

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
      _audioSub = pcmStream.listen((chunk) {
        _session?.sendAudio(chunk);
        final lvl = _computeLevel(chunk);
        if ((lvl - state.level).abs() > 0.02) {
          state = state.copyWith(level: lvl);
        }
      });

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

    // 關閉背景錄音前景服務(Android)。
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
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      state = state.copyWith(elapsed: state.elapsed + const Duration(seconds: 1));
    });
  }

  Future<void> _teardown() async {
    _timer?.cancel();
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
