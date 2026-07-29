import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/network/api_exception.dart';
import '../core/utils/think_parser.dart';
import '../models/chat_message.dart';
import 'service_providers.dart';

class AssistantState {
  const AssistantState({
    this.messages = const [],
    this.streaming = false,
    this.error,
  });

  final List<ChatMessage> messages;
  final bool streaming;
  final String? error;

  AssistantState copyWith({
    List<ChatMessage>? messages,
    bool? streaming,
    String? error,
    bool clearError = false,
  }) {
    return AssistantState(
      messages: messages ?? this.messages,
      streaming: streaming ?? this.streaming,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// 個人助理。arg 為會議範圍('' = 跨全部會議的 agentic RAG)。
final assistantControllerProvider =
    NotifierProvider.family<AssistantController, AssistantState, String>(
        AssistantController.new);

class AssistantController extends FamilyNotifier<AssistantState, String> {
  StreamSubscription<dynamic>? _sub;

  @override
  AssistantState build(String scope) {
    ref.onDispose(() => _sub?.cancel());
    return const AssistantState();
  }

  String? get _scopeId => arg.isEmpty ? null : arg;

  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || state.streaming) return;

    final userMsg = ChatMessage(role: ChatRole.user, content: trimmed);
    final assistantMsg = ChatMessage(
      role: ChatRole.assistant,
      content: '',
      isStreaming: true,
    );
    state = state.copyWith(
      messages: [...state.messages, userMsg, assistantMsg],
      streaming: true,
      clearError: true,
    );

    final parser = ThinkParser();
    final history = _windowedHistory(state.messages);

    _sub = ref
        .read(backendProvider)
        .chat(messages: history, meetingScopeId: _scopeId)
        .listen(
      (chunk) {
        if (chunk.textDelta != null) {
          parser.add(chunk.textDelta!);
          _updateLast(
            content: parser.visible,
            thinking: parser.hasThinking ? parser.thinking : null,
          );
        }
        if (chunk.done) _finish(parser);
      },
      onError: (e) {
        _finish(parser);
        state = state.copyWith(
          error: e is ApiException ? e.message : '助理連線失敗:$e',
        );
      },
      onDone: () => _finish(parser),
    );
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    final msgs = _cloneMessages();
    if (msgs.isNotEmpty) msgs.last.isStreaming = false;
    state = state.copyWith(messages: msgs, streaming: false);
  }

  void clear() {
    _sub?.cancel();
    state = const AssistantState();
  }

  void _updateLast({required String content, String? thinking}) {
    final msgs = _cloneMessages();
    if (msgs.isEmpty) return;
    final last = msgs.last;
    last.content = content;
    last.thinking = thinking;
    state = state.copyWith(messages: msgs);
  }

  void _finish(ThinkParser parser) {
    if (!state.streaming) return;
    parser.flush();
    final msgs = _cloneMessages();
    if (msgs.isNotEmpty) {
      msgs.last
        ..content = parser.visible
        ..thinking = parser.hasThinking ? parser.thinking : null
        ..isStreaming = false;
    }
    state = state.copyWith(messages: msgs, streaming: false);
  }

  List<ChatMessage> _cloneMessages() =>
      state.messages.map((m) => m.copyWith()).toList();

  /// 滑動視窗 + 字元預算,避免爆 context(交接文件第 2 節)。
  List<ChatMessage> _windowedHistory(List<ChatMessage> all) {
    // 送出正在串流的最後一則空 assistant 訊息沒有意義,排除它。
    final usable = all
        .where((m) => !(m.role == ChatRole.assistant && m.content.isEmpty))
        .toList();
    var window = usable.length > AppConfig.assistantMaxMessages
        ? usable.sublist(usable.length - AppConfig.assistantMaxMessages)
        : usable;

    var chars = window.fold<int>(0, (sum, m) => sum + m.content.length);
    while (window.length > 1 && chars > AppConfig.assistantCharBudget) {
      chars -= window.first.content.length;
      window = window.sublist(1);
    }
    return window;
  }
}
