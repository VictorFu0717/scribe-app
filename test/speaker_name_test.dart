import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:meeting_assistant/models/meeting.dart';
import 'package:meeting_assistant/models/transcript_segment.dart';
import 'package:meeting_assistant/providers/meetings_controller.dart';
import 'package:meeting_assistant/providers/service_providers.dart';
import 'package:meeting_assistant/providers/settings_controller.dart';
import 'package:meeting_assistant/providers/speaker_names_controller.dart';
import 'package:meeting_assistant/providers/transcript_edits_controller.dart';
import 'package:meeting_assistant/services/export_service.dart';
import 'package:meeting_assistant/services/mock_backend.dart';
import 'package:meeting_assistant/services/speaker_name_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

TranscriptSegment seg(String text, String? speaker, int ms) => TranscriptSegment(
    id: 's$ms', text: text, isFinal: true, speaker: speaker, startMs: ms);

void main() {
  setUpAll(() => initializeDateFormatting('zh_TW', null));
  group('套用說話者設定', () {
    final segments = [
      seg('第一句', '說話者 1', 0),
      seg('第二句', '說話者 2', 5000),
      seg('第三句', '說話者 1', 10000),
    ];

    test('改名套用到該說話者的所有段落', () {
      final out = applySpeakerPrefs(
          segments, const SpeakerPrefs(names: {'說話者 1': '小明'}));
      expect(out.map((s) => s.speaker), ['小明', '說話者 2', '小明']);
    });

    test('指派只影響那一段', () {
      final out = applySpeakerPrefs(
        segments,
        const SpeakerPrefs(
          names: {'說話者 1': '小明', '說話者 2': '小美'},
          assignments: {
            'ms:0': SpeakerAssignment(speaker: '說話者 2', original: '說話者 1'),
          },
        ),
      );
      // 第一句改判給小美,第三句仍是小明。
      expect(out.map((s) => s.speaker), ['小美', '小美', '小明']);
    });

    test('指派存原始標籤,所以之後改名會跟著變(不會留舊名字)', () {
      const assignments = {
        'ms:0': SpeakerAssignment(speaker: '說話者 2', original: '說話者 1'),
      };
      final before = applySpeakerPrefs(segments,
          const SpeakerPrefs(names: {'說話者 2': '小美'}, assignments: assignments));
      expect(before.first.speaker, '小美');

      // 把說話者 2 再改名成小華 —— 被指派過去的那段也要變。
      final after = applySpeakerPrefs(segments,
          const SpeakerPrefs(names: {'說話者 2': '小華'}, assignments: assignments));
      expect(after.first.speaker, '小華',
          reason: '若指派存的是顯示名稱,這段會卡在舊名字');
    });

    test('原始說話者不吻合就不套用指派 —— 重新轉錄後不該指派到別人身上', () {
      // 重新轉錄後,同一個時間點變成說話者 3 說的。
      final reTranscribed = [seg('第一句', '說話者 3', 0)];
      final out = applySpeakerPrefs(
        reTranscribed,
        const SpeakerPrefs(assignments: {
          'ms:0': SpeakerAssignment(speaker: '說話者 2', original: '說話者 1'),
        }),
      );
      expect(out.single.speaker, '說話者 3');
    });

    test('沒有設定時回傳原本的 list', () {
      expect(identical(applySpeakerPrefs(segments, const SpeakerPrefs()),
          segments), isTrue);
    });

    test('沒開 diarization(speaker 為 null)不受影響', () {
      final noSpeaker = [seg('一句話', null, 0)];
      final out = applySpeakerPrefs(
          noSpeaker, const SpeakerPrefs(names: {'說話者 1': '小明'}));
      expect(out.single.speaker, isNull);
    });
  });

  group('SpeakerPrefsController', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<ProviderContainer> container() async {
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        backendProvider.overrideWithValue(MockBackend()),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('改名會持久化;改回原標籤等於取消', () async {
      final c = await container();
      final n = c.read(speakerPrefsProvider('m1').notifier);
      await n.rename('說話者 1', '小明');
      expect(c.read(speakerPrefsProvider('m1')).displayName('說話者 1'), '小明');

      // 直接從 store 讀,確認真的寫進去了。
      expect(c.read(speakerNameStoreProvider).prefsFor('m1').names['說話者 1'],
          '小明');

      await n.rename('說話者 1', '說話者 1');
      expect(c.read(speakerPrefsProvider('m1')).names, isEmpty,
          reason: '留著「改成和原本一樣」的記錄沒有意義');
    });

    test('指派回原本的人等於取消指派', () async {
      final c = await container();
      final n = c.read(speakerPrefsProvider('m1').notifier);
      final s = seg('句', '說話者 1', 0);

      await n.assign(s, 0, '說話者 2');
      expect(c.read(speakerPrefsProvider('m1')).assignments, isNotEmpty);

      await n.assign(s, 0, '說話者 1');
      expect(c.read(speakerPrefsProvider('m1')).assignments, isEmpty);
    });

    test('指派存的必須是原始標籤,不是顯示名稱', () async {
      final c = await container();
      final n = c.read(speakerPrefsProvider('m1').notifier);
      await n.rename('說話者 2', '小美'); // 先改名,才有「顯示名稱 ≠ 標籤」的情境

      await n.assign(seg('句', '說話者 1', 0), 0, '說話者 2');
      expect(c.read(speakerPrefsProvider('m1')).assignments['ms:0']!.speaker,
          '說話者 2',
          reason: '存顯示名稱的話,之後這人再改名,這段會卡在舊名字');

      // 驗證後果:再改名一次,被指派的那段要跟著變。
      await n.rename('說話者 2', '小華');
      final out = applySpeakerPrefs(
          [seg('句', '說話者 1', 0)], c.read(speakerPrefsProvider('m1')));
      expect(out.single.speaker, '小華');
    });

    test('新增說話者會拿到不重複的鍵', () async {
      final c = await container();
      final n = c.read(speakerPrefsProvider('m1').notifier);
      final k1 = await n.addSpeaker('小美');
      final k2 = await n.addSpeaker('小華');
      expect(k1, isNot(k2));
      expect(k1.startsWith(SpeakerNameStore.customPrefix), isTrue);
      expect(c.read(speakerPrefsProvider('m1')).displayName(k1), '小美');
    });

    test('不同會議互不干擾', () async {
      final c = await container();
      await c.read(speakerPrefsProvider('m1').notifier).rename('說話者 1', '小明');
      expect(c.read(speakerPrefsProvider('m2')).names, isEmpty);
    });

    test('壞掉的資料不該讓逐字稿讀不出來', () async {
      SharedPreferences.setMockInitialValues(
          {'speaker_prefs.m1': '{壞掉的 JSON'});
      final c = await container();
      expect(c.read(speakerPrefsProvider('m1')).isEmpty, isTrue);
    });
  });

  group('與逐字稿讀取入口整合', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('改名後 transcriptProvider 立刻反映,且不進 loading', () async {
      final prefs = await SharedPreferences.getInstance();
      final backend = MockBackend();
      final c = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        backendProvider.overrideWithValue(backend),
      ]);
      addTearDown(c.dispose);

      final id = (await backend.listMeetings()).first.id;
      final sub = c.listen(transcriptProvider(id), (_, __) {});
      addTearDown(sub.close);
      await c.read(rawTranscriptProvider(id).future);

      final before = c.read(transcriptProvider(id)).requireValue;
      final target = before.firstWhere((s) => s.speaker != null).speaker!;

      await c.read(speakerPrefsProvider(id).notifier).rename(target, '小明');

      final after = c.read(transcriptProvider(id));
      expect(after.isLoading, isFalse, reason: '一進 loading 捲動位置就會歸零');
      final renamed = after.requireValue;
      expect(renamed.where((s) => s.speaker == target), isEmpty);
      expect(renamed.where((s) => s.speaker == '小明'), isNotEmpty);
    });

    test('文字修訂與說話者設定可同時生效', () async {
      final prefs = await SharedPreferences.getInstance();
      final backend = MockBackend();
      final c = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        backendProvider.overrideWithValue(backend),
      ]);
      addTearDown(c.dispose);

      final id = (await backend.listMeetings()).first.id;
      final sub = c.listen(transcriptProvider(id), (_, __) {});
      addTearDown(sub.close);
      await c.read(rawTranscriptProvider(id).future);

      final raw = c.read(rawTranscriptProvider(id)).requireValue;
      final i = raw.indexWhere((s) => s.speaker != null);
      expect(i, isNot(-1), reason: '前提:mock 資料有說話者');

      await c.read(transcriptEditsProvider(id).notifier)
          .edit(raw[i], i, '改過的文字');
      await c.read(speakerPrefsProvider(id).notifier)
          .rename(raw[i].speaker!, '小明');

      final out = c.read(transcriptProvider(id)).requireValue;
      expect(out[i].text, '改過的文字');
      expect(out[i].speaker, '小明');

      // 匯出必須跟畫面一致(先前踩過「畫面有、匯出沒有」)。
      final txt = ExportService.buildTranscriptText(
          Meeting(id: id, title: 't', createdAt: DateTime(2026, 8, 23)), out);
      expect(txt, contains('小明'));
      expect(txt, contains('改過的文字'));
      expect(txt, isNot(contains(raw[i].speaker!)));
    });
  });
}
