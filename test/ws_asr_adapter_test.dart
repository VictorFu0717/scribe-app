import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meeting_assistant/core/storage/token_storage.dart';
import 'package:meeting_assistant/services/backend.dart';
import 'package:meeting_assistant/services/http_backend.dart';
import 'package:meeting_assistant/models/transcription_config.dart';

/// 起一個模擬 scribe `/ws/asr` 的本地 WebSocket server:
/// 收到 config 後主動送兩個累積式 partial,收到 {type:end} 回 final。
Future<HttpServer> _startFakeScribe({List<String>? received}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    if (!WebSocketTransformer.isUpgradeRequest(req)) {
      req.response.statusCode = 404;
      await req.response.close();
      return;
    }
    final ws = await WebSocketTransformer.upgrade(req);
    ws.listen((msg) async {
      if (msg is! String) return; // 忽略二進位音訊
      received?.add(msg);
      final ctrl = jsonDecode(msg) as Map<String, dynamic>;
      if (ctrl['type'] == 'config') {
        // 預覽:tentative 灰字
        ws.add(jsonEncode({
          'type': 'partial',
          'tentative': '你好',
          'segments': <dynamic>[],
        }));
        // 第一句定稿(累積 segments;帶說話者)
        ws.add(jsonEncode({
          'type': 'partial',
          'tentative': '',
          'segments': [
            {'speaker': '說話者 1', 'text': '你好世界'}
          ],
        }));
      } else if (ctrl['type'] == 'end') {
        ws.add(jsonEncode({
          'type': 'final',
          'text': '你好世界',
          'segments': [
            {'speaker': '說話者 1', 'text': '你好世界'}
          ],
        }));
      }
    });
  });
  return server;
}

void main() {
  test('WS adapter 對接 /ws/asr:累積式 partial/final → 快照', () async {
    final received = <String>[];
    final server = await _startFakeScribe(received: received);
    addTearDown(() => server.close(force: true));

    final backend = HttpBackend(
      baseUrl: 'http://${server.address.address}:${server.port}',
      tokenStorage: TokenStorage(),
    );

    final session = backend.openTranscription(
      meetingId: 'm1',
      config: const TranscriptionConfig(diarization: true, speakerCount: 2),
    );

    final updates = <TranscriptUpdate>[];
    session.updates.listen(updates.add);

    // 等第一個快照到(server 收到 config 後才推)。
    for (var i = 0; i < 50 && updates.isEmpty; i++) {
      await Future.delayed(const Duration(milliseconds: 20));
    }
    await session.stop(); // 送 {type:end},等 final

    // 送出的第一則控制訊息應是 config,且帶 diarization / speaker_count / meeting_id
    final cfg = jsonDecode(received.first) as Map<String, dynamic>;
    expect(cfg['type'], 'config');
    expect(cfg['diarization'], true);
    expect(cfg['speaker_count'], 2);
    expect(cfg['meeting_id'], 'm1');
    expect(received.any((m) => jsonDecode(m)['type'] == 'end'), isTrue);

    // 過程中出現過預覽(tentative)
    expect(updates.any((u) => u.partial?.text == '你好'), isTrue);

    // 最終快照:一段定稿、帶說話者、無預覽
    final last = updates.last;
    expect(last.partial, isNull);
    expect(last.finalSegments.length, 1);
    expect(last.finalSegments.first.text, '你好世界');
    expect(last.finalSegments.first.speaker, '說話者 1');
    expect(last.finalSegments.first.isFinal, isTrue);
  });
}
