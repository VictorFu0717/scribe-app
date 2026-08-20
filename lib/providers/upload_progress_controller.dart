import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 整檔上傳的階段。上傳只是其中一段 —— 前後還有複製與壓縮,都可能要好幾十秒,
/// 全部顯示成「上傳中」會讓使用者以為卡住。
enum UploadPhase {
  idle,

  /// 建立會議、把檔案複製到 App 目錄(大檔複製本身就要一段時間)。
  preparing,

  /// 正在上傳,有百分比可顯示。
  uploading,

  /// 位元組送完了,但 server 還在收尾(存檔、建立轉錄工作)才會回應。
  processing,

  /// 上傳完成,正在壓縮本機副本(一小時 110MB → 約 8MB)。
  compressing,
}

/// 整檔上傳的進度狀態。
class UploadProgressState {
  const UploadProgressState({
    this.phase = UploadPhase.idle,
    this.sent = 0,
    this.total = 0,
  });

  final UploadPhase phase;
  final int sent;
  final int total;

  bool get isActive => phase != UploadPhase.idle;

  /// 0..1 的進度;總量未知時回 null(進度條應改用不確定樣式)。
  double? get fraction {
    if (total <= 0) return null;
    return (sent / total).clamp(0.0, 1.0);
  }

  /// 整數百分比;總量未知時回 null。
  int? get percent {
    final f = fraction;
    return f == null ? null : (f * 100).round();
  }

  UploadProgressState copyWith({UploadPhase? phase, int? sent, int? total}) =>
      UploadProgressState(
        phase: phase ?? this.phase,
        sent: sent ?? this.sent,
        total: total ?? this.total,
      );
}

/// 整檔上傳的進度來源。由匯入流程與「重新轉錄」共用,UI 直接 watch。
///
/// 放在 provider 而非各畫面的 local state:上傳由 `importAudioFile` 這類跨畫面的
/// 流程驅動,且同一份進度要餵給不同進入點的對話框。
class UploadProgressController extends Notifier<UploadProgressState> {
  /// 上次回報的百分比,用來節流。
  int _lastPercent = -1;

  @override
  UploadProgressState build() => const UploadProgressState();

  void begin([UploadPhase phase = UploadPhase.preparing]) {
    _lastPercent = -1;
    state = UploadProgressState(phase: phase);
  }

  void setPhase(UploadPhase phase) {
    if (state.phase == phase) return;
    state = state.copyWith(phase: phase);
  }

  /// 接收 `Backend.uploadAudio` 的位元組進度。
  ///
  /// **節流**:百分比沒變就不更新 state。上傳一小時的錄音會被呼叫上千次
  /// (約每 64KB 一次),照單全收會讓 UI 每秒重繪數十次。
  void onBytes(int sent, int total) {
    final percent = total <= 0 ? -1 : (sent / total * 100).round();
    final finished = total > 0 && sent >= total;

    // 送完最後一個位元組 ≠ server 已回應:它還要存檔、建立轉錄工作。停在 100%
    // 不動會讓使用者以為當掉,所以改顯示「server 處理中」。
    final phase = finished ? UploadPhase.processing : UploadPhase.uploading;

    if (percent == _lastPercent && phase == state.phase) return;
    _lastPercent = percent;
    state = UploadProgressState(phase: phase, sent: sent, total: total);
  }

  void reset() {
    _lastPercent = -1;
    state = const UploadProgressState();
  }
}

final uploadProgressProvider =
    NotifierProvider<UploadProgressController, UploadProgressState>(
        UploadProgressController.new);
