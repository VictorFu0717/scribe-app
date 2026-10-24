import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meeting_assistant/core/network/api_exception.dart';
import 'package:meeting_assistant/providers/meetings_controller.dart';
import 'package:meeting_assistant/providers/service_providers.dart';
import 'package:meeting_assistant/providers/settings_controller.dart';
import 'package:meeting_assistant/services/mock_backend.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FailingDelete extends MockBackend {
  @override
  Future<void> deleteMeeting(String id) async =>
      throw ApiException('網路連線失敗', statusCode: null);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory docs;
  setUp(() => docs = Directory.systemTemp.createTempSync('docs'));
  tearDown(() => docs.deleteSync(recursive: true));

  File put(String name, {int bytes = 2048}) =>
      File('${docs.path}/$name')..writeAsBytesSync(List.filled(bytes, 1));

  group('LocalRecordingStore 的檔案操作', () {
    test('一場會議的所有檔案都找得到,別場的一個都不碰', () async {
      SharedPreferences.setMockInitialValues({});
      final store = LocalRecordingStore(await SharedPreferences.getInstance(),
          documentsDir: docs.path);
      put('rec_m1.wav');
      put('rec_m1.m4a', bytes: 0); // 早期壓縮失敗留下的空檔
      put('rec_m1.pcm'); // 錄到一半留下的原始檔
      put('import_m1.mp3');
      put('rec_m1x.wav'); // 別場:id 只是開頭相同
      put('rec_m2.wav');
      put('notes.txt'); // 不是錄音

      final mine = store.filesFor('m1').map((f) => f.path.split('/').last).toSet();
      expect(mine, {'rec_m1.wav', 'rec_m1.m4a', 'rec_m1.pcm', 'import_m1.mp3'});

      expect(await store.deleteFor('m1'), 4);
      final left = docs.listSync().map((e) => e.path.split('/').last).toSet();
      expect(left, {'rec_m1x.wav', 'rec_m2.wav', 'notes.txt'});
    });

    test('allFiles 依檔名辨識會議並帶出大小與類型', () async {
      SharedPreferences.setMockInitialValues({});
      final store = LocalRecordingStore(await SharedPreferences.getInstance(),
          documentsDir: docs.path);
      put('rec_a1.wav', bytes: 100);
      put('import_b2.m4a', bytes: 50);
      put('readme.md');
      final files = store.allFiles();
      expect(files.map((f) => f.meetingId).toSet(), {'a1', 'b2'});
      final imp = files.firstWhere((f) => f.meetingId == 'b2');
      expect(imp.imported, isTrue);
      expect(imp.size, 50);
    });
  });

  group('刪除會議', () {
    late SharedPreferences prefs;

    Future<ProviderContainer> containerWith(MockBackend backend) async {
      SharedPreferences.setMockInitialValues({
        'local_audio.m001': 'rec_m001.wav',
        'transcript_edits.m001': '{"ms:0":{"text":"改過","original":"原文"}}',
        'speaker_prefs.m001': '{"names":{"說話者 1":"小明"},"assignments":{}}',
        'meeting_translation.m001': '1|zh|en',
        'local_audio.m002': 'rec_m002.wav',
      });
      prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        documentsDirProvider.overrideWithValue(docs.path),
        backendProvider.overrideWithValue(backend),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('server 刪除成功後,手機上的錄音與本機記錄一併清掉', () async {
      put('rec_m001.wav');
      put('rec_m001.m4a');
      put('rec_m002.wav');
      final c = await containerWith(MockBackend());

      await c.read(meetingsListProvider.notifier).delete('m001');

      final left = docs.listSync().map((e) => e.path.split('/').last).toSet();
      expect(left, {'rec_m002.wav'}, reason: '別場會議的錄音不能被動到');
      for (final k in [
        'local_audio.m001',
        'transcript_edits.m001',
        'speaker_prefs.m001',
        'meeting_translation.m001',
      ]) {
        expect(prefs.containsKey(k), isFalse, reason: '$k 應該被清掉');
      }
      expect(prefs.getString('local_audio.m002'), 'rec_m002.wav');
    });

    test('server 刪除失敗時保留錄音 —— 免得 server 上會議還在、錄音卻沒了', () async {
      put('rec_m001.wav');
      final c = await containerWith(_FailingDelete());

      await expectLater(
          c.read(meetingsListProvider.notifier).delete('m001'), throwsA(isA<ApiException>()));

      expect(File('${docs.path}/rec_m001.wav').existsSync(), isTrue);
      expect(prefs.getString('local_audio.m001'), 'rec_m001.wav');
    });
  });
}
