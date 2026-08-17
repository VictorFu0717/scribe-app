import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meeting_assistant/core/storage/token_storage.dart';
import 'package:meeting_assistant/models/transcription_config.dart';
import 'package:meeting_assistant/services/backend.dart';
import 'package:meeting_assistant/services/http_backend.dart';

/// 開飛航模式時 iOS 不會給 socket 任何錯誤事件 —— 連線變成黑洞:沒有 FIN、
/// 沒有 onError/onDone。實測「開飛航模式完全沒有紅字」就是因為偵測不到。
/// 這裡用 TCP proxy 忠實重現那個情境(丟棄封包但不關閉連線)。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('連線靜默死亡也要偵測到並轉入重連;健康連線不得被心跳誤殺', () async {
    // 一個最小的 WS server(dart:io 會在協議層自動回 pong,同 uvicorn 行為)。
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final ws = await WebSocketTransformer.upgrade(req);
      ws.listen((_) {}, onError: (_) {}, onDone: () {});
    });

    var blackhole = false;
    final proxy = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    proxy.listen((client) async {
      final up = await Socket.connect(InternetAddress.loopbackIPv4, server.port);
      client.listen((d) { if (!blackhole) up.add(d); },
          onDone: up.destroy, onError: (_) => up.destroy());
      up.listen((d) { if (!blackhole) client.add(d); },
          onDone: client.destroy, onError: (_) => client.destroy());
    });

    final backend = HttpBackend(
      baseUrl: 'http://127.0.0.1:${proxy.port}',
      tokenStorage: TokenStorage(),
    );
    final session = backend.openTranscription(
      meetingId: 'm1',
      config: const TranscriptionConfig(),
    );
    final seen = <TranscriptionLinkState>[];
    session.linkState.listen(seen.add);

    // 撐過數個心跳週期 —— 健康的連線不該被 pingInterval 誤判。
    await Future<void>.delayed(const Duration(seconds: 13));
    expect(seen, contains(TranscriptionLinkState.online));
    expect(seen.last, TranscriptionLinkState.online,
        reason: '健康連線被心跳誤殺會導致正常網路下也一直重連');

    // 變成黑洞:ping 送不出去、pong 收不到,但 socket 看起來還開著。
    blackhole = true;
    await Future<void>.delayed(const Duration(seconds: 14));

    expect(seen.last, TranscriptionLinkState.reconnecting,
        reason: '沒收到 pong 就該判定斷線 —— 先前完全偵測不到,連紅字都不會出現');
    expect(session.droppedAt, isNotNull, reason: 'UI 靠它顯示警示與中斷時長');

    await session.stop();
    backend.dispose();
    await proxy.close();
    await server.close(force: true);
  }, timeout: const Timeout(Duration(seconds: 90)));
}
