import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:meeting_assistant/models/meeting.dart';
import 'package:meeting_assistant/models/transcript_segment.dart';
import 'package:meeting_assistant/providers/meetings_controller.dart';
import 'package:meeting_assistant/providers/service_providers.dart';
import 'package:meeting_assistant/providers/settings_controller.dart';
import 'package:meeting_assistant/providers/transcript_edits_controller.dart';
import 'package:meeting_assistant/services/export_service.dart';
import 'package:meeting_assistant/services/mock_backend.dart';
import 'package:meeting_assistant/services/transcript_edit_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

TranscriptSegment seg(String id, String text, {int? startMs}) =>
    TranscriptSegment(id: id, text: text, isFinal: true, startMs: startMs);

/// 數 getTranscript 被呼叫幾次 —— 用來確認編輯不會害它重抓一次。
class _CountingBackend extends MockBackend {
  int transcriptFetches = 0;

  @override
  Future<List<TranscriptSegment>> getTranscript(String meetingId) {
    transcriptFetches++;
    return super.getTranscript(meetingId);
  }
}

void main() {
  // 匯出會用到日期格式化。
  setUpAll(() => initializeDateFormatting('zh_TW', null));
  group('修訂的 key', () {
    test('有時間戳時用時間戳 —— 比 server 的 id 穩定', () {
      expect(TranscriptEditStore.keyFor(seg('a', 'x', startMs: 5000), 0),
          'ms:5000');
    });

    test('沒有時間戳的片段不得共用同一個 key', () {
      // server 沒給 id 也沒給時間戳時,model 會讓所有片段的 id 都變成 '-'。
      // 若拿 id 當 key,改一句會改到整份逐字稿。
      final a = TranscriptSegment.fromJson({'text': '甲', 'is_final': true});
      final b = TranscriptSegment.fromJson({'text': '乙', 'is_final': true});
      expect(a.id, b.id, reason: '前提:這種情況下 id 真的會重複');
      expect(TranscriptEditStore.keyFor(a, 0),
          isNot(TranscriptEditStore.keyFor(b, 1)));
    });
  });

  group('套用修訂', () {
    test('只改對應的那一段', () {
      final segments = [
        seg('1', '今天要討論預算', startMs: 0),
        seg('2', '請大家準備資料', startMs: 5000),
      ];
      final edited = applyTranscriptEdits(segments, {
        'ms:5000': const TranscriptEdit(
            text: '請大家準備簡報', original: '請大家準備資料'),
      });
      expect(edited[0].text, '今天要討論預算');
      expect(edited[1].text, '請大家準備簡報');
      // 其他欄位不能被弄丟(時間戳沒了就不能跳回去聽)。
      expect(edited[1].startMs, 5000);
      expect(edited[1].id, '2');
    });

    test('原文不吻合就不套用 —— 重新轉錄後修訂不該落到別的句子上', () {
      // 重新轉錄後,同一個時間點可能變成完全不同的句子。
      final reTranscribed = [seg('9', '完全不同的內容', startMs: 5000)];
      final edited = applyTranscriptEdits(reTranscribed, {
        'ms:5000': const TranscriptEdit(
            text: '請大家準備簡報', original: '請大家準備資料'),
      });
      expect(edited.single.text, '完全不同的內容',
          reason: '硬套會把修訂蓋到不相干的句子上');
    });

    test('逐字稿還原回原本內容時,修訂會再次生效', () {
      const edits = {
        'ms:5000': TranscriptEdit(text: '簡報', original: '資料'),
      };
      expect(applyTranscriptEdits([seg('9', '別的句子', startMs: 5000)], edits)
          .single.text, '別的句子');
      expect(applyTranscriptEdits([seg('2', '資料', startMs: 5000)], edits)
          .single.text, '簡報');
    });

    test('沒有修訂時回傳原本的 list,不做多餘複製', () {
      final segments = [seg('1', '甲', startMs: 0)];
      expect(identical(applyTranscriptEdits(segments, const {}), segments),
          isTrue);
    });
  });

  group('TranscriptEditStore 持久化', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('存了之後讀得回來,且不同會議互不干擾', () async {
      final store = TranscriptEditStore(await SharedPreferences.getInstance());
      await store.save('m1', 'ms:0', text: '改過', original: '原文');
      expect(store.editsFor('m1')['ms:0']!.text, '改過');
      expect(store.editsFor('m2'), isEmpty);
    });

    test('改回原文等於取消修訂', () async {
      final store = TranscriptEditStore(await SharedPreferences.getInstance());
      await store.save('m1', 'ms:0', text: '改過', original: '原文');
      await store.save('m1', 'ms:0', text: '原文', original: '原文');
      expect(store.editsFor('m1'), isEmpty,
          reason: '留著一條「改成和原文一樣」的修訂會讓「已編輯」標記騙人');
    });

    test('壞掉的資料不該讓整份逐字稿讀不出來', () async {
      SharedPreferences.setMockInitialValues(
          {'transcript_edits.m1': '{不是合法 JSON'});
      final store = TranscriptEditStore(await SharedPreferences.getInstance());
      expect(store.editsFor('m1'), isEmpty);
    });
  });

  // 先前踩過「畫面有翻譯但匯出沒有」,所以這裡驗到底:改完字之後,
  // 逐字稿的**單一讀取入口**要跟著變,匯出才不會與畫面不一致。
  group('編輯後,讀取入口與匯出都要跟著變', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('transcriptProvider 會疊上修訂,匯出的 .txt 也含修訂', () async {
      final prefs = await SharedPreferences.getInstance();
      final backend = MockBackend();
      final container = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        backendProvider.overrideWithValue(backend),
      ]);
      addTearDown(container.dispose);

      // 取一場 mock 會議既有的逐字稿。
      final meetings = await backend.listMeetings();
      final id = meetings.first.id;
      await container.read(rawTranscriptProvider(id).future);
      final before = container.read(transcriptProvider(id)).requireValue;
      expect(before, isNotEmpty);

      final target = before.first;
      await container
          .read(transcriptEditsProvider(id).notifier)
          .edit(target, 0, '這是我改過的內容');

      final after = container.read(transcriptProvider(id)).requireValue;
      expect(after.first.text, '這是我改過的內容');
      // 其餘片段不能受影響。
      expect(after.length, before.length);
      if (before.length > 1) expect(after[1].text, before[1].text);

      final txt = ExportService.buildTranscriptText(
          Meeting(id: id, title: 't', createdAt: DateTime(2026, 8, 22)), after);
      expect(txt, contains('這是我改過的內容'));
      expect(txt, isNot(contains(target.text)));
    });

    test('還原後回到 server 的原文', () async {
      final prefs = await SharedPreferences.getInstance();
      final backend = MockBackend();
      final container = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        backendProvider.overrideWithValue(backend),
      ]);
      addTearDown(container.dispose);

      final id = (await backend.listMeetings()).first.id;
      await container.read(rawTranscriptProvider(id).future);
      final before = container.read(transcriptProvider(id)).requireValue;
      final original = before.first.text;
      final notifier = container.read(transcriptEditsProvider(id).notifier);

      await notifier.edit(before.first, 0, '改過');
      final edited = container.read(transcriptProvider(id)).requireValue;
      expect(edited.first.text, '改過');

      // 注意:傳入的是**目前顯示**的片段(已是修訂後),還原仍要能對上。
      await notifier.revert(edited.first, 0);
      final reverted = container.read(transcriptProvider(id)).requireValue;
      expect(reverted.first.text, original);
    });

    test('反覆編輯不會讓修訂失效 —— original 必須一直是 server 的原文', () async {
      final prefs = await SharedPreferences.getInstance();
      final backend = MockBackend();
      final container = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        backendProvider.overrideWithValue(backend),
      ]);
      addTearDown(container.dispose);

      final id = (await backend.listMeetings()).first.id;
      await container.read(rawTranscriptProvider(id).future);
      final before = container.read(transcriptProvider(id)).requireValue;
      final notifier = container.read(transcriptEditsProvider(id).notifier);

      await notifier.edit(before.first, 0, '第一次改');
      var cur = container.read(transcriptProvider(id)).requireValue;

      // 第二次改的是「已修訂過」的片段。若把它的文字當成 original 存下去,
      // 就再也對不上 server 回來的原文,修訂會整條失效。
      await notifier.edit(cur.first, 0, '第二次改');
      cur = container.read(transcriptProvider(id)).requireValue;
      expect(cur.first.text, '第二次改');
    });
  });

  // 實測回報:改完一段之後畫面跳回第一行。原因是 transcriptProvider 曾是
  // FutureProvider 卻 watch 了修訂 —— 一改字整個 future 重跑、重抓 server,
  // 期間 AsyncValue 進入 loading,畫面整份換成轉圈圈,ListView 重建就捲回頂端。
  group('編輯不該讓畫面重建(捲動位置才留得住)', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('編輯後不進入 loading,且不重新向 server 抓逐字稿', () async {
      final prefs = await SharedPreferences.getInstance();
      final backend = _CountingBackend();
      final container = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        backendProvider.overrideWithValue(backend),
      ]);
      addTearDown(container.dispose);

      final id = (await backend.listMeetings()).first.id;
      // 保持訂閱,否則 provider 會被回收、重讀時又抓一次而測不到重點。
      final sub = container.listen(transcriptProvider(id), (_, __) {});
      addTearDown(sub.close);

      await container.read(rawTranscriptProvider(id).future);
      final fetchesBefore = backend.transcriptFetches;
      final before = container.read(transcriptProvider(id)).requireValue;

      await container
          .read(transcriptEditsProvider(id).notifier)
          .edit(before.first, 0, '改過的內容');

      final after = container.read(transcriptProvider(id));
      expect(after.isLoading, isFalse,
          reason: '一進 loading,畫面就整份換成轉圈圈,捲動位置必定歸零');
      expect(after.hasValue, isTrue);
      expect(after.requireValue.first.text, '改過的內容');
      expect(backend.transcriptFetches, fetchesBefore,
          reason: '改個字不該再打一次 server(慢、耗流量,還會讓畫面閃一下)');
    });
  });
}
