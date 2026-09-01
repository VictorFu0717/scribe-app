import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meeting_assistant/core/network/api_exception.dart';
import 'package:meeting_assistant/models/meeting.dart';
import 'package:meeting_assistant/models/transcript_segment.dart';
import 'package:meeting_assistant/providers/meetings_controller.dart';
import 'package:meeting_assistant/providers/service_providers.dart';
import 'package:meeting_assistant/providers/settings_controller.dart';
import 'package:meeting_assistant/providers/speaker_names_controller.dart';
import 'package:meeting_assistant/providers/transcript_edits_controller.dart';
import 'package:meeting_assistant/providers/transcript_sync_controller.dart';
import 'package:meeting_assistant/services/mock_backend.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 記錄 PUT 收到什麼,並可指定失敗。
class _SpyBackend extends MockBackend {
  List<TranscriptSegment>? pushed;
  var pushes = 0;
  ApiException? failWith;

  @override
  Future<void> putTranscript(
      String meetingId, List<TranscriptSegment> segments) async {
    pushes++;
    if (failWith != null) throw failWith!;
    pushed = List.of(segments);
    return super.putTranscript(meetingId, segments);
  }
}

void main() {
  late ProviderContainer c;
  late _SpyBackend backend;
  late String id;
  late List<TranscriptSegment> raw;

  Future<void> setUpMeeting() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    backend = _SpyBackend();
    c = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      backendProvider.overrideWithValue(backend),
    ]);
    addTearDown(c.dispose);

    id = (await backend.listMeetings()).first.id;
    // 保持訂閱,provider 才不會被回收。
    addTearDown(c.listen(transcriptProvider(id), (_, __) {}).close);
    await c.read(rawTranscriptProvider(id).future);
    raw = c.read(rawTranscriptProvider(id)).requireValue;
  }

  group('同步成功', () {
    setUp(setUpMeeting);

    test('送出的是「已套用本機修訂」的整份逐字稿', () async {
      await c
          .read(transcriptEditsProvider(id).notifier)
          .edit(raw.first, 0, '我改過的文字');
      await c
          .read(speakerPrefsProvider(id).notifier)
          .rename(raw.first.speaker!, '小明');

      expect(await c.read(transcriptSyncProvider(id).notifier).push(), isTrue);

      expect(backend.pushes, 1);
      expect(backend.pushed, hasLength(raw.length),
          reason: 'PUT 是整組取代 —— 只送改過的那幾段會把其他段落刪掉');
      expect(backend.pushed!.first.text, '我改過的文字');
      expect(backend.pushed!.first.speaker, '小明');
      // 時間戳不能弄丟,否則點時間戳跳轉就失效了。
      expect(backend.pushed!.first.startMs, raw.first.startMs);
    });

    test('成功後清掉本機修訂(server 成為單一真相),但畫面內容不變', () async {
      await c
          .read(transcriptEditsProvider(id).notifier)
          .edit(raw.first, 0, '我改過的文字');
      await c.read(transcriptSyncProvider(id).notifier).push();

      expect(c.read(transcriptEditsProvider(id)), isEmpty);
      expect(c.read(speakerPrefsProvider(id)).isEmpty, isTrue);
      // 內容仍是改過的 —— raw 直接採用剛送出去的那份。
      expect(c.read(transcriptProvider(id)).requireValue.first.text, '我改過的文字');
    });

    test('成功後不重抓 server,也不進 loading(否則畫面閃、捲動歸零)', () async {
      final fetchesBefore = backend.transcriptFetches;
      await c
          .read(transcriptEditsProvider(id).notifier)
          .edit(raw.first, 0, '改過');
      await c.read(transcriptSyncProvider(id).notifier).push();

      expect(c.read(transcriptProvider(id)).isLoading, isFalse);
      expect(backend.transcriptFetches, fetchesBefore,
          reason: '剛送出去的內容就是 server 的內容,沒有理由再抓一次');
    });

    test('沒有未同步的修訂時 hasPending 為 false', () async {
      expect(c.read(transcriptSyncProvider(id).notifier).hasPending, isFalse);
      await c
          .read(transcriptEditsProvider(id).notifier)
          .edit(raw.first, 0, '改過');
      expect(c.read(transcriptSyncProvider(id).notifier).hasPending, isTrue);
      await c.read(transcriptSyncProvider(id).notifier).push();
      expect(c.read(transcriptSyncProvider(id).notifier).hasPending, isFalse);
    });
  });

  group('同步失敗', () {
    setUp(setUpMeeting);

    test('保留本機修訂,並帶出 server 的原因', () async {
      backend.failWith = ApiException('會議狀態為 transcribing,請等轉錄完成後再編輯',
          statusCode: 409);
      await c
          .read(transcriptEditsProvider(id).notifier)
          .edit(raw.first, 0, '改過');

      expect(await c.read(transcriptSyncProvider(id).notifier).push(), isFalse);

      // 修訂不能丟 —— 使用者打的字是資料。
      expect(c.read(transcriptEditsProvider(id)), isNotEmpty);
      expect(c.read(transcriptProvider(id)).requireValue.first.text, '改過');
      expect(c.read(transcriptSyncProvider(id)).error,
          contains('請等轉錄完成後再編輯'));
      expect(c.read(transcriptSyncProvider(id).notifier).hasPending, isTrue);
    });

    test('離線失敗後可重試成功', () async {
      backend.failWith = ApiException.network(Exception('offline'));
      await c
          .read(transcriptEditsProvider(id).notifier)
          .edit(raw.first, 0, '改過');
      expect(await c.read(transcriptSyncProvider(id).notifier).push(), isFalse);

      backend.failWith = null;
      expect(await c.read(transcriptSyncProvider(id).notifier).push(), isTrue);
      expect(c.read(transcriptEditsProvider(id)), isEmpty);
      expect(backend.pushed!.first.text, '改過');
    });

    test('有空白段落時不打 server —— 先在本機說清楚', () async {
      await c.read(transcriptEditsProvider(id).notifier).edit(raw.first, 0, '   ');
      expect(await c.read(transcriptSyncProvider(id).notifier).push(), isFalse);
      expect(backend.pushes, 0, reason: '明知會被 400 擋下就不必送');
      expect(c.read(transcriptSyncProvider(id)).error, contains('空白'));
    });
  });

  group('MockBackend 的防呆與 server 一致', () {
    setUp(setUpMeeting);

    test('轉錄中回 409', () async {
      final m = await backend.createMeeting(title: '錄音中的會議');
      expect(m.status, MeetingStatus.recording);
      expect(
        () => backend.putTranscript(m.id, const [
          TranscriptSegment(id: 's', text: '甲', isFinal: true),
        ]),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 409)),
      );
    });

    test('空白段落回 400', () async {
      expect(
        () => backend.putTranscript(id, const [
          TranscriptSegment(id: 's', text: '  ', isFinal: true),
        ]),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 400)),
      );
    });
  });
}
