import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meeting_assistant/core/theme/app_theme.dart';
import 'package:meeting_assistant/models/meeting_diagram.dart';
import 'package:meeting_assistant/services/image_saver.dart';
import 'package:meeting_assistant/widgets/diagram_card.dart';

const _diagram = MeetingDiagram(
  kind: 'flow',
  code: 'flowchart TD\n  n1["需求確認"] --> n2["上線"]',
);

final _jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const saveImage = MethodChannel('app/save_image');
  const saveFile = MethodChannel('app/save_file');

  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('diagram_download');
    ImageSaver.tempDir = () async => tmp;
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(saveImage, null);
    messenger.setMockMethodCallHandler(saveFile, null);
    tmp.deleteSync(recursive: true);
  });

  group('檔名', () {
    test('含圖種與時間,副檔名 jpg', () {
      expect(diagramFileName(_diagram, DateTime(2026, 10, 5, 9, 7)),
          '會議助理_流程圖_20261005_0907.jpg');
      expect(
          diagramFileName(
              const MeetingDiagram(kind: 'mindmap', code: 'x'), DateTime(2026, 1, 1)),
          contains('心智圖'));
    });
  });

  group('iOS:存進照片', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);

    test('把圖片寫成檔案交給原生端,成功回報「已存到照片」', () async {
      MethodCall? seen;
      List<int>? bytesAtCall;
      messenger.setMockMethodCallHandler(saveImage, (call) async {
        seen = call;
        // 原生端要讀得到檔案 —— 確認呼叫當下檔案存在且內容正確
        bytesAtCall = File(call.arguments['path'] as String).readAsBytesSync();
        return 'ok';
      });

      final r = await ImageSaver.saveJpeg(_jpeg, fileName: 'a.jpg');
      expect(seen!.method, 'saveToPhotos');
      expect(bytesAtCall, _jpeg);
      expect(r.ok, isTrue);
      expect(r.message, contains('照片'));
      // 暫存檔用完要刪,不然每存一次就多一個檔案
      expect(tmp.listSync(), isEmpty);
    });

    test('沒有權限時告訴使用者去哪裡開', () async {
      messenger.setMockMethodCallHandler(saveImage, (_) async => 'denied');
      final r = await ImageSaver.saveJpeg(_jpeg, fileName: 'a.jpg');
      expect(r.ok, isFalse);
      expect(r.message, contains('設定'));
      expect(r.message, contains('僅加入照片'));
    });
  });

  group('Android', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);

    test('Android 10 以上直接寫進相簿', () async {
      MethodCall? seen;
      messenger.setMockMethodCallHandler(saveImage, (call) async {
        seen = call;
        return 'ok';
      });
      final r = await ImageSaver.saveJpeg(_jpeg, fileName: '會議助理_流程圖.jpg');
      expect(seen!.method, 'saveToGallery');
      expect(seen!.arguments['name'], '會議助理_流程圖.jpg');
      expect(r.ok, isTrue);
      expect(r.message, contains('Pictures/會議助理'));
    });

    test('原生端的錯誤原因要帶出來,不能只說失敗', () async {
      messenger.setMockMethodCallHandler(
          saveImage, (_) async => 'error: 無法在相簿建立檔案');
      final r = await ImageSaver.saveJpeg(_jpeg, fileName: 'a.jpg');
      expect(r.ok, isFalse);
      expect(r.message, contains('無法在相簿建立檔案'));
    });

    test('Android 9 以下改走「另存新檔」,且指定 image/jpeg', () async {
      messenger.setMockMethodCallHandler(saveImage, (_) async => 'legacy');
      MethodCall? saf;
      messenger.setMockMethodCallHandler(saveFile, (call) async {
        saf = call;
        return true;
      });
      final r = await ImageSaver.saveJpeg(_jpeg, fileName: 'a.jpg');
      expect(saf!.method, 'save');
      expect(saf!.arguments['mime'], 'image/jpeg');
      expect(saf!.arguments['name'], 'a.jpg');
      expect(r.ok, isTrue);
    });

    test('使用者取消「另存新檔」時不顯示錯誤', () async {
      messenger.setMockMethodCallHandler(saveImage, (_) async => 'legacy');
      messenger.setMockMethodCallHandler(saveFile, (_) async => false);
      final r = await ImageSaver.saveJpeg(_jpeg, fileName: 'a.jpg');
      expect(r.ok, isFalse);
      expect(r.message, isNull, reason: '那是使用者自己的選擇,不必跳錯誤訊息');
    });
  });

  testWidgets('圖還沒畫好時,下載按鈕是停用的', (tester) async {
    // 單元測試裡 WebView 畫不出圖,正好用來驗證「沒有東西可存時不能按」
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(
        body: SingleChildScrollView(child: DiagramCard(diagram: _diagram)),
      ),
    ));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final button = tester.widget<IconButton>(find.ancestor(
      of: find.byIcon(Icons.download_rounded),
      matching: find.byType(IconButton),
    ));
    expect(button.onPressed, isNull);
    expect(button.tooltip, contains('JPG'));
  });
}
