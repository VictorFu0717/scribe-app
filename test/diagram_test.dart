import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:meeting_assistant/models/chat_message.dart';
import 'package:meeting_assistant/models/meeting_diagram.dart';
import 'package:meeting_assistant/services/backend.dart';
import 'package:meeting_assistant/services/http_backend.dart';
import 'package:http/http.dart' as http;
import 'package:meeting_assistant/core/storage/token_storage.dart';
import 'package:meeting_assistant/models/auth_token.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meeting_assistant/providers/assistant_controller.dart';
import 'package:meeting_assistant/providers/service_providers.dart';
import 'package:meeting_assistant/providers/settings_controller.dart';
import 'package:meeting_assistant/services/mock_backend.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeTokenStorage extends TokenStorage {
  @override
  Future<AuthToken?> read() async => null;
  @override
  Future<void> write(AuthToken token) async {}
  @override
  Future<void> clear() async {}
}

HttpBackend _backend(MockClient client) => HttpBackend(
      baseUrl: 'http://x',
      tokenStorage: _FakeTokenStorage(),
      client: client,
    );

http.StreamedResponse _sse(String body) => http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      200,
      headers: {'content-type': 'text/event-stream'},
    );

/// server app/diagram.py 實際產出的形狀。
const _flowCode = 'flowchart TD\n'
    '  n1["需求確認"] --> n2{"預算足夠?"}\n'
    '  n2 -->|"是"| n3["進入開發"]';

void main() {
  group('MeetingDiagram.fromJson', () {
    test('解析 server 的 diagram 事件', () {
      final d = MeetingDiagram.fromJson({
        'type': 'diagram',
        'meeting_id': 'm1',
        'kind': 'relation',
        'code': 'graph LR\n  n1["小明"] -->|"負責"| n2["API"]',
        'source': 'summary',
      })!;
      expect(d.kind, 'relation');
      expect(d.kindLabel, '關係圖');
      expect(d.sourceLabel, '依據摘要');
      expect(d.meetingId, 'm1');
      expect(d.code, contains('graph LR'));
    });

    test('帶 hint(沒有摘要時 server 會提醒)', () {
      final d = MeetingDiagram.fromJson({
        'type': 'diagram',
        'kind': 'flow',
        'code': _flowCode,
        'source': 'transcript',
        'hint': '這場會議還沒有摘要,這張圖是直接讀逐字稿畫的。',
      })!;
      expect(d.sourceLabel, '依據逐字稿');
      expect(d.hint, contains('還沒有摘要'));
    });

    test('不是 diagram 事件就回 null', () {
      expect(MeetingDiagram.fromJson({'delta': '一般文字'}), isNull);
    });

    test('沒有 code 的事件回 null —— 不要渲染出一塊空白', () {
      expect(
          MeetingDiagram.fromJson(
              {'type': 'diagram', 'kind': 'flow', 'code': '   '}),
          isNull);
      expect(MeetingDiagram.fromJson({'type': 'diagram', 'kind': 'flow'}),
          isNull);
    });

    test('未知的 kind 仍可顯示,不讓整張圖消失', () {
      final d = MeetingDiagram.fromJson(
          {'type': 'diagram', 'kind': 'sankey', 'code': _flowCode})!;
      expect(d.kindLabel, '圖表');
      expect(d.sourceLabel, isNull);
    });

    test('四種圖種都有中文名稱', () {
      String label(String k) =>
          MeetingDiagram(kind: k, code: _flowCode).kindLabel;
      expect(label('flow'), '流程圖');
      expect(label('relation'), '關係圖');
      expect(label('timeline'), '時間軸');
      expect(label('mindmap'), '心智圖');
    });
  });

  group('chat SSE', () {
    test('diagram 事件變成 ChatChunk.diagram,不會被當成文字印出來', () async {
      final client = MockClient.streaming((_, __) async => _sse(
            'data: {"delta":"我幫你畫了一張圖。"}\n\n'
            'data: ${jsonEncode({
                  'type': 'diagram',
                  'meeting_id': 'm1',
                  'kind': 'flow',
                  'code': _flowCode,
                  'source': 'summary',
                })}\n\n'
            'data: [DONE]\n\n',
          ));

      final chunks = await _backend(client)
          .chat(messages: [ChatMessage(role: ChatRole.user, content: '畫圖')])
          .toList();

      final diagrams = chunks.where((c) => c.diagram != null).toList();
      expect(diagrams, hasLength(1));
      expect(diagrams.single.diagram!.code, _flowCode);

      // 關鍵:原始碼不能混進文字 —— 否則使用者會看到一整段 Mermaid。
      final text =
          chunks.map((c) => c.textDelta ?? '').join();
      expect(text, '我幫你畫了一張圖。');
      expect(text, isNot(contains('flowchart')));
    });

    test('一則回答可以有多張圖', () async {
      String ev(String kind) => 'data: ${jsonEncode({
            'type': 'diagram',
            'kind': kind,
            'code': kind == 'flow' ? _flowCode : 'graph LR\n  a["x"] --> b["y"]',
          })}\n\n';
      final client = MockClient.streaming(
          (_, __) async => _sse('${ev('flow')}${ev('relation')}data: [DONE]\n\n'));

      final chunks = await _backend(client)
          .chat(messages: [ChatMessage(role: ChatRole.user, content: '畫圖')])
          .toList();
      expect(
          chunks.where((c) => c.diagram != null).map((c) => c.diagram!.kind),
          ['flow', 'relation']);
    });

    // 圖的事件是一長串 JSON(含中文),網路封包可能從任何位置切開 ——
    // 包括一個中文字的 UTF-8 位元組中間。解析器若處理不好,整張圖會被丟掉,
    // 使用者只看到文字。用最極端的切法驗證不會發生。
    test('事件被切成任意大小的封包(含切在中文字中間)也能完整收到圖', () async {
      final code = 'flowchart TD\n' +
          List.generate(12, (i) => '  n$i["第 $i 個步驟:確認需求與預算"] --> n${i + 1}["下一步"]')
              .join('\n');
      final body = utf8.encode(
          'data: {"delta":"我幫你畫了一張圖。"}\n\n'
          'data: ${jsonEncode({'type': 'diagram', 'kind': 'flow', 'code': code, 'source': 'summary'})}\n\n'
          'data: {"delta":"這張圖呈現了流程。"}\n\n'
          'data: [DONE]\n\n');

      for (final chunkSizes in <List<int>>[
        [1],            // 每塊 1 個位元組
        [2, 3, 5, 7],   // 不規則大小,會切在多位元組字元中間
        [4096],         // 一次全部
      ]) {
        final chunks = <List<int>>[];
        var i = 0, k = 0;
        while (i < body.length) {
          final n = chunkSizes[k++ % chunkSizes.length];
          chunks.add(body.sublist(i, (i + n).clamp(0, body.length)));
          i += n;
        }
        final client = MockClient.streaming((_, __) async => http.StreamedResponse(
            Stream.fromIterable(chunks), 200,
            headers: {'content-type': 'text/event-stream'}));

        final got = await _backend(client)
            .chat(messages: [ChatMessage(role: ChatRole.user, content: '畫圖')])
            .toList();
        final diagrams = got.where((c) => c.diagram != null).toList();
        expect(diagrams, hasLength(1), reason: '切法 $chunkSizes 時圖不見了');
        expect(diagrams.single.diagram!.code, code,
            reason: '切法 $chunkSizes 時原始碼不完整');
        expect(got.map((c) => c.textDelta ?? '').join(),
            '我幫你畫了一張圖。這張圖呈現了流程。');
      }
    });

    test('沒有圖時行為不變(純文字)', () async {
      final client = MockClient.streaming((_, __) async =>
          _sse('data: {"delta":"一般回答"}\n\ndata: [DONE]\n\n'));
      final chunks = await _backend(client)
          .chat(messages: [ChatMessage(role: ChatRole.user, content: 'hi')])
          .toList();
      expect(chunks.where((c) => c.diagram != null), isEmpty);
      expect(chunks.map((c) => c.textDelta ?? '').join(), '一般回答');
    });
  });

  group('ChatMessage', () {
    test('copyWith 保留圖(串流更新文字時不能把圖弄丟)', () {
      final m = ChatMessage(
        role: ChatRole.assistant,
        content: '',
        diagrams: [const MeetingDiagram(kind: 'flow', code: _flowCode)],
      );
      final updated = m.copyWith(content: '說明文字');
      expect(updated.diagrams, hasLength(1));
      expect(updated.content, '說明文字');
    });

    test('預設沒有圖', () {
      expect(ChatMessage(role: ChatRole.user, content: 'x').diagrams, isEmpty);
    });
  });

  group('助理 controller', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<ProviderContainer> container(Backend backend) async {
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        backendProvider.overrideWithValue(backend),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('圖掛到助理那則訊息上,使用者訊息不受影響', () async {
      final c = await container(_DiagramBackend());
      final n = c.read(assistantControllerProvider('').notifier);
      await n.send('幫我畫流程圖');
      // 等串流跑完。
      for (var i = 0; i < 50 && c.read(assistantControllerProvider('')).streaming; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      final msgs = c.read(assistantControllerProvider('')).messages;
      expect(msgs.first.isUser, isTrue);
      expect(msgs.first.diagrams, isEmpty);
      expect(msgs.last.diagrams, hasLength(1));
      expect(msgs.last.diagrams.single.kind, 'flow');
      // 文字照常收到,且不含原始碼。
      expect(msgs.last.content, '這張圖呈現決策路徑。');
      expect(msgs.last.content, isNot(contains('flowchart')));
    });

    test('圖比文字先到也要留得住(工具先跑完才輪到 LLM 講話)', () async {
      final c = await container(_DiagramFirstBackend());
      final n = c.read(assistantControllerProvider('').notifier);
      await n.send('畫圖');
      for (var i = 0; i < 50 && c.read(assistantControllerProvider('')).streaming; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      final last = c.read(assistantControllerProvider('')).messages.last;
      expect(last.diagrams, hasLength(1),
          reason: '文字更新會 clone 訊息 —— clone 時把圖弄丟就看不到圖了');
      expect(last.content, '說明');
    });
  });
}

/// 先文字、後圖。
class _DiagramBackend extends MockBackend {
  @override
  Stream<ChatChunk> chat({
    required List<ChatMessage> messages,
    String? meetingScopeId,
  }) async* {
    yield const ChatChunk(textDelta: '這張圖呈現決策路徑。');
    yield const ChatChunk(
        diagram: MeetingDiagram(kind: 'flow', code: _flowCode));
    yield const ChatChunk(done: true);
  }
}

/// 先圖、後文字(工具先跑完的情況)。
class _DiagramFirstBackend extends MockBackend {
  @override
  Stream<ChatChunk> chat({
    required List<ChatMessage> messages,
    String? meetingScopeId,
  }) async* {
    yield const ChatChunk(
        diagram: MeetingDiagram(kind: 'flow', code: _flowCode));
    yield const ChatChunk(textDelta: '說明');
    yield const ChatChunk(done: true);
  }
}
