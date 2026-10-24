import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:meeting_assistant/core/theme/app_theme.dart';
import 'package:meeting_assistant/features/settings/storage_cleanup_screen.dart';
import 'package:meeting_assistant/models/meeting.dart';
import 'package:meeting_assistant/providers/service_providers.dart';
import 'package:meeting_assistant/providers/settings_controller.dart';
import 'package:meeting_assistant/services/mock_backend.dart';
import 'package:meeting_assistant/services/storage_cleanup.dart';
import 'package:shared_preferences/shared_preferences.dart';

LocalAudioFile _f(String id, {int size = 1000, bool imported = false, String ext = 'wav'}) =>
    LocalAudioFile(
      file: File('/x/${imported ? 'import' : 'rec'}_$id.$ext'),
      meetingId: id,
      imported: imported,
      size: size,
      modified: DateTime(2026, 9, 10),
    );

/// 回傳指定的會議清單(模擬 server 的 GET /meetings)。
class _ListBackend extends MockBackend {
  _ListBackend(this.ids, {this.fail = false});
  final List<String> ids;
  final bool fail;

  @override
  Future<List<Meeting>> listMeetings() async {
    if (fail) throw Exception('offline');
    return [
      for (final id in ids)
        Meeting(id: id, title: id, createdAt: DateTime(2026, 9, 1)),
    ];
  }
}

/// 讓真實的檔案 IO 跑完。
///
/// testWidgets 跑在 FakeAsync 裡:真實 IO 要在 runAsync 中才會完成,而它的
/// 後續步驟(await 之後的程式)又要靠 pump 推進。刪多個檔案是一連串 await,
/// 所以要交替多輪,只跑一輪的話會停在一半。
Future<void> _settleIo(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('zh_TW', null));

  group('analyzeLocalAudio', () {
    test('找不到對應會議的列為可清理;還在的會議只有 0 位元組的才列', () {
      final scan = analyzeLocalAudio([
        _f('alive'),
        _f('alive', size: 0, ext: 'm4a'),
        _f('gone'),
        _f('gone2', imported: true),
      ], {'alive'});
      expect(scan.orphans.map((f) => f.meetingId), ['gone', 'gone2']);
      expect(scan.empty.single.meetingId, 'alive');
      expect(scan.empty.single.size, 0);
      // 還在的會議、有內容的錄音,絕對不能出現在可刪除清單
      expect(scan.removable.where((f) => f.meetingId == 'alive' && f.size > 0),
          isEmpty);
    });

    test('每個錄音都有對應會議時,沒有可清理的', () {
      final scan = analyzeLocalAudio([_f('a'), _f('b')], {'a', 'b', 'c'});
      expect(scan.removable, isEmpty);
      expect(scan.totalBytes, 2000);
    });

    test('App 錄的 WAV 可由大小推算長度(每秒 32,000 位元組)', () {
      // 實際案例:61 MB 的 rec_58270311abe5.wav ≈ 33 分鐘
      final d = estimateRecordingLength(_f('m', size: 61 * 1024 * 1024));
      expect(d!.inMinutes, 33);
      expect(estimateRecordingLength(_f('m', imported: true)), isNull,
          reason: '匯入的音檔格式不一定,推算不準就不要顯示');
      expect(estimateRecordingLength(_f('m', ext: 'm4a')), isNull);
    });
  });

  group('清理錄音檔畫面', () {
    late Directory docs;
    setUp(() => docs = Directory.systemTemp.createTempSync('cleanup'));
    tearDown(() => docs.deleteSync(recursive: true));

    File put(String name, {int bytes = 2048}) =>
        File('${docs.path}/$name')..writeAsBytesSync(List.filled(bytes, 1));

    Future<SharedPreferences> pump(WidgetTester tester, MockBackend backend,
        {bool mock = false, Map<String, Object> prefs = const {}}) async {
      SharedPreferences.setMockInitialValues({'settings.use_mock': mock, ...prefs});
      final p = await SharedPreferences.getInstance();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(p),
          documentsDirProvider.overrideWithValue(docs.path),
          backendProvider.overrideWithValue(backend),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: const StorageCleanupScreen()),
      ));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      return p;
    }

    testWidgets('Mock 模式下不能清理(會議清單是假的)', (tester) async {
      put('rec_real.wav');
      await pump(tester, _ListBackend(const []), mock: true);
      expect(find.textContaining('Mock'), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsNothing);
    });

    testWidgets('拿不到會議清單就不清理,並可重試', (tester) async {
      put('rec_real.wav');
      await pump(tester, _ListBackend(const [], fail: true));
      expect(find.textContaining('為避免誤刪'), findsOneWidget);
      expect(find.text('重試'), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsNothing,
          reason: '清單不完整時,還在的會議會被誤判成已刪除');
    });

    testWidgets('只列出找不到會議的錄音;刪除後還在的會議的錄音不受影響', (tester) async {
      put('rec_alive.wav');
      put('rec_gone.wav');
      put('import_gone2.mp3');
      final prefs = await pump(tester, _ListBackend(const ['alive']),
          prefs: {'local_audio.gone': 'rec_gone.wav', 'speaker_prefs.gone': '{}'});

      expect(find.byType(CheckboxListTile), findsNWidgets(2));
      expect(find.textContaining('rec_alive.wav'), findsNothing);

      await tester.tap(find.textContaining('刪除所選'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, '刪除'));
      await _settleIo(tester);

      final left = docs.listSync().map((e) => e.path.split('/').last).toSet();
      expect(left, {'rec_alive.wav'});
      expect(prefs.containsKey('local_audio.gone'), isFalse);
      expect(prefs.containsKey('speaker_prefs.gone'), isFalse);
    });

    testWidgets('取消勾選的檔案不會被刪', (tester) async {
      put('rec_gone.wav');
      put('rec_keep.wav');
      await pump(tester, _ListBackend(const []));

      await tester.tap(find.textContaining('rec_keep.wav'));
      await tester.pump();
      await tester.tap(find.textContaining('刪除所選'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, '刪除'));
      await _settleIo(tester);

      final left = docs.listSync().map((e) => e.path.split('/').last).toSet();
      expect(left, {'rec_keep.wav'});
    });
  });
}
