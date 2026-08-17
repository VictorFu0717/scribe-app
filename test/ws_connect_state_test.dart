import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meeting_assistant/core/storage/token_storage.dart';
import 'package:meeting_assistant/models/transcription_config.dart';
import 'package:meeting_assistant/services/backend.dart';
import 'package:meeting_assistant/services/http_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 找一個確定沒人在聽的 port(綁完立刻關掉)。
  Future<int> deadPort() async {
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    await probe.close();
    return port;
  }

  group('WS 連線狀態', () {
    test('連不上時不得回報 online —— 必須持續處於重連中', () async {
      final backend = HttpBackend(
        baseUrl: 'http://127.0.0.1:${await deadPort()}',
        tokenStorage: TokenStorage(),
      );
      final session = backend.openTranscription(
        meetingId: 'm1',
        config: const TranscriptionConfig(),
      );
      final seen = <TranscriptionLinkState>[];
      final sub = session.linkState.listen(seen.add);

      await Future<void>.delayed(const Duration(seconds: 2));

      // 這是先前的 bug:IOWebSocketChannel.connect() 不阻塞,於是根本沒連上
      // 就被當成 online —— 警示紅字閃一下就消失、音訊往死掉的 sink 送。
      expect(seen, isNot(contains(TranscriptionLinkState.online)),
          reason: '沒連上就不該回報 online');
      expect(seen, contains(TranscriptionLinkState.reconnecting));
      expect(session.droppedAt, isNotNull, reason: 'UI 需要它來持續顯示警示');

      await sub.cancel();
      await session.stop();
      backend.dispose();
    });

    test('斷線中按停止要立刻回,不能卡在等 final 的逾時', () async {
      final backend = HttpBackend(
        baseUrl: 'http://127.0.0.1:${await deadPort()}',
        tokenStorage: TokenStorage(),
      );
      final session = backend.openTranscription(
        meetingId: 'm1',
        config: const TranscriptionConfig(),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));

      final sw = Stopwatch()..start();
      await session.stop();
      sw.stop();

      // 從未連上 → 沒有 final 可等。先前會等滿 15 秒逾時。
      expect(sw.elapsed, lessThan(const Duration(seconds: 3)));
      backend.dispose();
    });
  });
}
