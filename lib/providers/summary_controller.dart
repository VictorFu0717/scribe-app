import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_exception.dart';
import '../models/summary.dart';
import 'meetings_controller.dart';
import 'service_providers.dart';

class SummaryState {
  const SummaryState({
    this.streamingText = '',
    this.summary,
    this.streaming = false,
    this.loading = false,
    this.error,
  });

  /// SSE 串流中的即時文字(邊產邊顯示)。
  final String streamingText;

  /// 最終結構化摘要。
  final MeetingSummary? summary;
  final bool streaming;
  final bool loading;
  final String? error;

  bool get hasContent => summary != null || streamingText.isNotEmpty;

  SummaryState copyWith({
    String? streamingText,
    MeetingSummary? summary,
    bool? streaming,
    bool? loading,
    String? error,
    bool clearError = false,
  }) {
    return SummaryState(
      streamingText: streamingText ?? this.streamingText,
      summary: summary ?? this.summary,
      streaming: streaming ?? this.streaming,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

final summaryControllerProvider =
    NotifierProvider.family<SummaryController, SummaryState, String>(
        SummaryController.new);

class SummaryController extends FamilyNotifier<SummaryState, String> {
  StreamSubscription<dynamic>? _sub;

  @override
  SummaryState build(String meetingId) {
    ref.onDispose(() => _sub?.cancel());
    _loadExisting(meetingId);
    return const SummaryState(loading: true);
  }

  Future<void> _loadExisting(String meetingId) async {
    try {
      final existing = await ref.read(backendProvider).getSummary(meetingId);
      state = SummaryState(summary: existing, loading: false);
    } catch (_) {
      state = const SummaryState(loading: false);
    }
  }

  /// 觸發 server 產生摘要(SSE 串流)。
  Future<void> generate() async {
    if (state.streaming) return;
    final meetingId = arg;
    _sub?.cancel();
    state = const SummaryState(streaming: true, streamingText: '');

    final buffer = StringBuffer();
    _sub = ref.read(backendProvider).summarize(meetingId).listen(
      (chunk) {
        if (chunk.textDelta != null) {
          buffer.write(chunk.textDelta);
          state = state.copyWith(streamingText: buffer.toString());
        }
        if (chunk.summary != null) {
          state = state.copyWith(summary: chunk.summary);
        }
        if (chunk.done) {
          state = state.copyWith(streaming: false);
          ref.invalidate(meetingsListProvider);
        }
      },
      onError: (e) {
        state = state.copyWith(
          streaming: false,
          error: e is ApiException ? e.message : '產生摘要失敗:$e',
        );
      },
      onDone: () {
        if (state.streaming) state = state.copyWith(streaming: false);
      },
    );
  }
}
