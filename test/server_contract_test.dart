import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:meeting_assistant/core/storage/token_storage.dart';
import 'package:meeting_assistant/models/auth_token.dart';
import 'package:meeting_assistant/models/chat_message.dart';
import 'package:meeting_assistant/models/meeting.dart';
import 'package:meeting_assistant/models/transcription_config.dart';
import 'package:meeting_assistant/services/http_backend.dart';

/// 記憶體 token 儲存,避免測試碰到 flutter_secure_storage 原生 channel。
class _FakeTokenStorage extends TokenStorage {
  @override
  Future<AuthToken?> read() async => null;
  @override
  Future<void> write(AuthToken token) async {}
  @override
  Future<void> clear() async {}
}

/// 這些測試把 App 的解析鎖定在 scribe server 的「實際」回傳形狀
/// (取自 server repo 的 db.py / summarize.py / chat_qa.py),避免日後 drift。

http.StreamedResponse _json(Object obj, [int status = 200]) =>
    http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(obj))),
      status,
      headers: {'content-type': 'application/json'},
    );

http.StreamedResponse _sse(String body) => http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      200,
      headers: {'content-type': 'text/event-stream'},
    );

HttpBackend _backend(MockClient client) => HttpBackend(
      baseUrl: 'http://scribe.local:8005',
      tokenStorage: TokenStorage(),
      client: client,
    );

void main() {
  test('POST /auth/register:JSON body、解析 token 回應', () async {
    Map<String, dynamic>? body;
    Uri? url;
    final client = MockClient.streaming((req, bodyStream) async {
      url = req.url;
      body = jsonDecode(await bodyStream.bytesToString()) as Map<String, dynamic>;
      // server auth.py 的 _token_response 形狀
      return _json({
        'access_token': 'jwt-abc',
        'token_type': 'bearer',
        'expires_in': 43200,
        'user_id': 'u1',
        'username': 'alice',
      });
    });
    final backend = HttpBackend(
      baseUrl: 'http://scribe.local:8005',
      tokenStorage: _FakeTokenStorage(),
      client: client,
    );

    final token =
        await backend.register(username: 'alice', password: 'pw1234');

    expect(url?.path, '/auth/register');
    expect(body?['username'], 'alice');
    expect(body?['password'], 'pw1234');
    expect(token.accessToken, 'jwt-abc');
    expect(token.authorizationHeader, 'Bearer jwt-abc');
    expect(token.isExpired, isFalse); // expires_in=12h → 未過期
  });

  test('GET /meetings 解析 server 的 {items:[...]} 形狀', () async {
    final client = MockClient.streaming((req, _) async {
      expect(req.url.path, '/meetings');
      // server db._meeting_row 的實際形狀
      return _json({
        'items': [
          {
            'id': 'ab12cd34',
            'title': '產品週會',
            'created_at': '2026-07-23T08:00:00Z',
            'duration_sec': 2580,
            'status': 'ready',
            'has_summary': true,
            'audio_url': null,
          }
        ]
      });
    });
    final meetings = await _backend(client).listMeetings();
    expect(meetings.length, 1);
    expect(meetings.first.id, 'ab12cd34');
    expect(meetings.first.title, '產品週會');
    expect(meetings.first.durationSec, 2580);
    expect(meetings.first.hasSummary, isTrue);
  });

  test('DELETE /meetings/{id}:發出 DELETE、204 視為成功', () async {
    String? method;
    String? path;
    final client = MockClient.streaming((req, _) async {
      method = req.method;
      path = req.url.path;
      return http.StreamedResponse(const Stream.empty(), 204); // server 回 204 No Content
    });
    await _backend(client).deleteMeeting('ab12cd34');
    expect(method, 'DELETE');
    expect(path, '/meetings/ab12cd34');
  });

  test('GET transcript 解析 {segments:[{id:"s0",is_final,...}]}', () async {
    final client = MockClient.streaming((req, _) async {
      expect(req.url.path, '/meetings/m1/transcript');
      return _json({
        'segments': [
          {
            'id': 's0',
            'text': '我們先確認里程碑。',
            'speaker': '說話者 1',
            'is_final': true,
            'start_ms': 0,
            'end_ms': 3200,
          }
        ]
      });
    });
    final segs = await _backend(client).getTranscript('m1');
    expect(segs.length, 1);
    expect(segs.first.text, '我們先確認里程碑。');
    expect(segs.first.speaker, '說話者 1');
    expect(segs.first.isFinal, isTrue);
  });

  test('GET summary:404 → null;有資料 → 結構化解析', () async {
    final none = _backend(MockClient.streaming((req, _) async => _json({'detail': 'summary not found'}, 404)));
    expect(await none.getSummary('m1'), isNull);

    final has = _backend(MockClient.streaming((req, _) async => _json({
          'overview': '確認架構方向。',
          'key_points': ['重點一', '重點二'],
          'decisions': ['採用 server 集中式 ML'],
          'action_items': [
            {'task': '建立 API 契約', 'owner': '小林', 'due': '本週五'}
          ],
          'follow_ups': ['下週追蹤'],
        })));
    final s = await has.getSummary('m2');
    expect(s, isNotNull);
    expect(s!.overview, '確認架構方向。');
    expect(s.keyPoints.length, 2);
    expect(s.actionItems.single.owner, '小林');
    expect(s.actionItems.single.due, '本週五');
  });

  test('POST /meetings/{id}/summarize:delta 串流 + 結構化 JSON + [DONE]', () async {
    final client = MockClient.streaming((req, _) async {
      expect(req.method, 'POST');
      expect(req.url.path, '/meetings/m1/summarize');
      // server summarize.py 的實際 SSE:先 delta,再結構化,最後 [DONE]
      return _sse('data: {"delta":"本次會議"}\n\n'
          'data: {"delta":"確認了架構。"}\n\n'
          'data: {"overview":"確認架構方向。","key_points":["一","二"],'
          '"decisions":["採 server 集中"],"action_items":[{"task":"立 API","owner":"小林"}],'
          '"follow_ups":["下週追蹤"]}\n\n'
          'data: [DONE]\n\n');
    });
    final chunks = await _backend(client).summarize('m1').toList();
    final streamed =
        chunks.map((c) => c.textDelta ?? '').join();
    expect(streamed, '本次會議確認了架構。');
    // 最終結構化摘要應出現(done 或前一個 chunk)
    final summary = chunks.firstWhere((c) => c.summary != null).summary!;
    expect(summary.overview, '確認架構方向。');
    expect(summary.actionItems.single.task, '立 API');
    expect(chunks.last.done, isTrue);
  });

  test('單場助理 → POST /assistant/chat,body 帶 messages + meeting_id', () async {
    String? chatBody;
    final client = MockClient.streaming((req, bodyStream) async {
      expect(req.url.path, '/assistant/chat');
      chatBody = await bodyStream.bytesToString();
      return _sse('data: {"delta":"根據逐字稿,"}\n\n'
          'data: {"delta":"重點是先立契約。"}\n\n'
          'data: [DONE]\n\n');
    });

    final chunks = await _backend(client).chat(
      messages: [ChatMessage(role: ChatRole.user, content: '這場的重點?')],
      meetingScopeId: 'm1',
    ).toList();

    expect(chunks.map((c) => c.textDelta ?? '').join(), '根據逐字稿,重點是先立契約。');
    final body = jsonDecode(chatBody!) as Map<String, dynamic>;
    expect(body['meeting_id'], 'm1');
    expect((body['messages'] as List).last['content'], '這場的重點?');
  });

  test('跨會議助理 → POST /assistant/chat,不帶 meeting_id', () async {
    String? chatBody;
    final client = MockClient.streaming((req, bodyStream) async {
      expect(req.url.path, '/assistant/chat');
      chatBody = await bodyStream.bytesToString();
      return _sse('data: {"delta":"上週有兩項決議。"}\n\ndata: [DONE]\n\n');
    });

    final chunks = await _backend(client).chat(
      messages: [ChatMessage(role: ChatRole.user, content: '上週的決議?')],
    ).toList();

    expect(chunks.map((c) => c.textDelta ?? '').join(), '上週有兩項決議。');
    final body = jsonDecode(chatBody!) as Map<String, dynamic>;
    expect(body.containsKey('meeting_id'), isFalse);
  });

  test('上傳音檔 → POST /meetings/{id}/audio,diarization 走 multipart 表單欄位',
      () async {
    String? contentType;
    String? rawBody;
    final client = MockClient.streaming((req, bodyStream) async {
      expect(req.method, 'POST');
      expect(req.url.path, '/meetings/m1/audio');
      contentType = req.headers['content-type'];
      rawBody = await bodyStream.bytesToString();
      return _json({'id': 'm1', 'status': 'transcribing', 'duration_sec': 120});
    });

    // 建一個暫存音檔給 MultipartFile.fromPath 讀。
    final tmp = await File(
            '${Directory.systemTemp.path}/scribe_upload_test.wav')
        .create();
    await tmp.writeAsBytes([1, 2, 3, 4]);

    final m = await _backend(client).uploadAudio(
      'm1',
      tmp.path,
      config: const TranscriptionConfig(diarization: true),
    );
    await tmp.delete();

    expect(m.status, MeetingStatus.transcribing);
    expect(contentType, contains('multipart/form-data'));
    // diarization 應在 multipart body 中(表單欄位),而非 URL query。
    expect(rawBody, contains('name="diarization"'));
    expect(rawBody, contains('true'));
    expect(rawBody, contains('name="file"'));
  });

  // ── 會議標籤(server commit b965da6)──
  //
  // 契約直接取自 server repo 的 app/routers/meetings.py 與 app/db.py:
  //   GET   /meetings/tags        → {"tags":[{"tag":..,"count":..}]}
  //   PATCH /meetings/{id}        → 更新後的 meeting;沒帶的欄位不動
  //   meeting JSON 多了 "tags": [...]
  group('會議標籤', () {
    test('GET /meetings/tags 解析成 MeetingTag,並依 server 的排序原樣保留', () async {
      late Uri seen;
      final client = MockClient.streaming((req, _) async {
        seen = req.url;
        return _json({
          'tags': [
            {'tag': '專案會議', 'count': 5},
            {'tag': '每週會議', 'count': 2},
          ]
        });
      });
      final tags = await _backend(client).listTags();
      expect(seen.path, '/meetings/tags');
      expect(tags.map((t) => t.tag), ['專案會議', '每週會議']);
      expect(tags.first.count, 5);
    });

    test('GET /meetings/tags 回傳空清單時不炸', () async {
      final client = MockClient.streaming((_, __) async => _json({'tags': []}));
      expect(await _backend(client).listTags(), isEmpty);
    });

    test('PATCH 只帶要改的欄位 —— server 語意是「沒帶的不動」', () async {
      late String method;
      late Uri url;
      late Map<String, dynamic> body;
      final client = MockClient.streaming((req, bodyStream) async {
        method = req.method;
        url = req.url;
        body = jsonDecode(await bodyStream.bytesToString())
            as Map<String, dynamic>;
        return _json({
          'id': 'm1',
          'title': 't',
          'created_at': '2026-09-01T10:00:00Z',
          'status': 'ready',
          'tags': ['專案會議'],
        });
      });

      final m = await _backend(client)
          .updateMeeting('m1', tags: ['專案會議']);
      expect(method, 'PATCH');
      expect(url.path, '/meetings/m1');
      expect(body.containsKey('title'), isFalse,
          reason: '沒有要改標題就不能帶 title —— 帶 null 可能被當成要清空');
      expect(body['tags'], ['專案會議']);
      expect(m.tags, ['專案會議']);
    });

    test('PATCH 帶空陣列 = 清空標籤(不是「不動」)', () async {
      late Map<String, dynamic> body;
      final client = MockClient.streaming((req, bodyStream) async {
        body = jsonDecode(await bodyStream.bytesToString())
            as Map<String, dynamic>;
        return _json({
          'id': 'm1',
          'title': 't',
          'created_at': '2026-09-01T10:00:00Z',
          'status': 'ready',
          'tags': [],
        });
      });
      final m = await _backend(client).updateMeeting('m1', tags: []);
      expect(body['tags'], isEmpty);
      expect(body.containsKey('tags'), isTrue,
          reason: '清空必須把 tags 送出去,漏掉就變成「不動」');
      expect(m.tags, isEmpty);
    });

    test('meeting JSON 的 tags 被解析;舊資料沒有這個欄位時為空', () {
      final withTags = Meeting.fromJson({
        'id': 'm1',
        'title': 't',
        'created_at': '2026-09-01T10:00:00Z',
        'status': 'ready',
        'tags': ['專案會議', '每週會議'],
      });
      expect(withTags.tags, ['專案會議', '每週會議']);

      // server 說既有 DB 免遷移,所以舊會議可能完全沒有 tags 欄位。
      final legacy = Meeting.fromJson({
        'id': 'm2',
        'title': 't',
        'created_at': '2026-09-01T10:00:00Z',
        'status': 'ready',
      });
      expect(legacy.tags, isEmpty);
    });

    test('tags 欄位含非字串或空字串時濾掉,不產生垃圾標籤', () {
      // server 自己踩過 str(None) 變成標籤「None」的坑,App 端也別把髒資料放進來。
      final m = Meeting.fromJson({
        'id': 'm1',
        'title': 't',
        'created_at': '2026-09-01T10:00:00Z',
        'status': 'ready',
        'tags': ['專案會議', '', null, 42, '每週會議'],
      });
      expect(m.tags, ['專案會議', '每週會議']);
    });
  });
}
