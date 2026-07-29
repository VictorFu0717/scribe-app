import 'dart:async';
import 'dart:convert';

/// 一個 Server-Sent Event。
class SseEvent {
  const SseEvent({required this.event, required this.data});

  /// event 欄位(預設 'message')。
  final String event;

  /// data 欄位(多行會以 \n 串接)。
  final String data;
}

/// 把 HTTP streamed body(`Stream<List<int>>`)轉成 SSE 事件流。
///
/// 遵循 SSE 規格:以空行分隔事件,支援多行 `data:`、`event:` 欄位,
/// 忽略以 `:` 開頭的註解與 `id:`/`retry:`。
Stream<SseEvent> parseSse(Stream<List<int>> byteStream) {
  final controller = StreamController<SseEvent>();
  var eventName = 'message';
  final dataLines = <String>[];

  void dispatch() {
    if (dataLines.isEmpty && eventName == 'message') return;
    final data = dataLines.join('\n');
    if (data.isNotEmpty || eventName != 'message') {
      controller.add(SseEvent(event: eventName, data: data));
    }
    eventName = 'message';
    dataLines.clear();
  }

  final sub = byteStream
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen(
    (line) {
      if (line.isEmpty) {
        dispatch();
        return;
      }
      if (line.startsWith(':')) return; // 註解 / keep-alive
      final idx = line.indexOf(':');
      final field = idx == -1 ? line : line.substring(0, idx);
      var value = idx == -1 ? '' : line.substring(idx + 1);
      if (value.startsWith(' ')) value = value.substring(1);
      switch (field) {
        case 'data':
          dataLines.add(value);
          break;
        case 'event':
          eventName = value;
          break;
        default:
          break; // id / retry / 其他:忽略
      }
    },
    onError: controller.addError,
    onDone: () {
      dispatch();
      controller.close();
    },
    cancelOnError: true,
  );

  controller.onCancel = () => sub.cancel();
  return controller.stream;
}
