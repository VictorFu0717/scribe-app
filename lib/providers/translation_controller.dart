import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_exception.dart';
import 'service_providers.dart';
import 'settings_controller.dart';

/// 整篇逐字稿的留檔翻譯狀態(server 端 LLM,高品質)。
class TranslationState {
  const TranslationState({
    this.text = '',
    this.streaming = false,
    this.error,
    this.checked = false,
    this.target = '',
  });

  /// 目前譯文(串流中會逐步增長)。
  final String text;

  /// 是否正在串流翻譯。
  final bool streaming;
  final String? error;

  /// 是否已向 server 查過既有存檔(避免每次進頁面都重查/重翻)。
  final bool checked;

  /// 這份譯文對應的目標語言;設定改語言後會與目前設定不符,需重翻。
  final String target;

  bool get hasText => text.trim().isNotEmpty;

  TranslationState copyWith({
    String? text,
    bool? streaming,
    String? error,
    bool clearError = false,
    bool? checked,
    String? target,
  }) {
    return TranslationState(
      text: text ?? this.text,
      streaming: streaming ?? this.streaming,
      error: clearError ? null : (error ?? this.error),
      checked: checked ?? this.checked,
      target: target ?? this.target,
    );
  }
}

/// 每場會議一份翻譯狀態(arg = meetingId)。
final translationControllerProvider =
    NotifierProvider.family<TranslationController, TranslationState, String>(
        TranslationController.new);

class TranslationController extends FamilyNotifier<TranslationState, String> {
  StreamSubscription<dynamic>? _sub;

  @override
  TranslationState build(String meetingId) {
    ref.onDispose(() => _sub?.cancel());
    return const TranslationState();
  }

  String get _meetingId => arg;
  String get _target => ref.read(settingsProvider).translationTarget;

  /// 確保有譯文:先讀 server 存檔,沒有才實際翻譯(避免重複消耗 LLM)。
  /// 供「錄音結束後自動翻譯」與進入翻譯分頁時呼叫,重複呼叫安全。
  Future<void> ensureTranslated() async {
    if (state.streaming) return;
    final target = _target;
    // 已有這個語言的譯文就不用再做。
    if (state.checked && state.hasText && state.target == target) return;

    final backend = ref.read(backendProvider);
    try {
      final existing =
          await backend.getTranslation(_meetingId, target: target);
      if (existing != null && existing.trim().isNotEmpty) {
        state = state.copyWith(
            text: existing, checked: true, target: target, clearError: true);
        return;
      }
    } catch (_) {
      // 讀存檔失敗不阻斷,直接嘗試翻譯。
    }
    state = state.copyWith(checked: true);
    await translate();
  }

  /// 實際呼叫 server 翻譯(SSE 串流)。會覆蓋現有譯文。
  Future<void> translate() async {
    if (state.streaming) return;
    final target = _target;
    final backend = ref.read(backendProvider);

    state = state.copyWith(
        text: '', streaming: true, clearError: true, target: target);

    final done = Completer<void>();
    await _sub?.cancel();
    _sub = backend.translate(_meetingId, target: target).listen(
      (chunk) {
        if (chunk.error != null) {
          state = state.copyWith(error: chunk.error, streaming: false);
          if (!done.isCompleted) done.complete();
          return;
        }
        if (chunk.textDelta != null) {
          state = state.copyWith(text: state.text + chunk.textDelta!);
        }
        if (chunk.done) {
          state = state.copyWith(streaming: false, checked: true);
          if (!done.isCompleted) done.complete();
        }
      },
      onError: (e) {
        state = state.copyWith(
          error: e is ApiException ? e.message : '翻譯失敗:$e',
          streaming: false,
        );
        if (!done.isCompleted) done.complete();
      },
      onDone: () {
        if (state.streaming) {
          state = state.copyWith(streaming: false, checked: true);
        }
        if (!done.isCompleted) done.complete();
      },
      cancelOnError: true,
    );
    return done.future;
  }
}
