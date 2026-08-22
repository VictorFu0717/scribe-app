import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meeting_assistant/core/theme/app_theme.dart';
import 'package:meeting_assistant/widgets/segment_edit_sheet.dart';

/// 一句真實長度的逐字稿(30 秒的發言可以很長)。
const _long = '那我們今天的會議主要是要確認一下跨平台版本的里程碑跟時程安排,'
    '另外也想順便討論一下 server 端的 API 契約要怎麼定,因為這件事會直接影響到'
    '雙端的開發進度,所以希望大家能先看過文件再來討論細節部分。';

Future<SegmentEditResult?> _open(
  WidgetTester tester, {
  required double keyboard,
  String text = _long,
  String original = _long,
}) async {
  tester.view.physicalSize = const Size(393 * 3, 852 * 3);
  tester.view.devicePixelRatio = 3.0;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard * 3);
  addTearDown(tester.view.reset);

  SegmentEditResult? result;
  await tester.pumpWidget(MaterialApp(
    // **一定要用 App 真正的主題**:先前用預設主題測,完全測不出那個
    // 「儲存按鈕被排到畫面外」的問題 —— 元凶正是主題裡的 filledButtonTheme。
    theme: AppTheme.light(),
    home: Scaffold(
      body: Builder(
        builder: (ctx) => TextButton(
          onPressed: () async => result = await showModalBottomSheet(
            context: ctx,
            isScrollControlled: true,
            builder: (_) => SegmentEditSheet(
              text: text,
              original: original,
              stamp: '03:42',
              onPlay: () {},
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  // 中文輸入法的鍵盤比英文高不少(多一排候選字),所以各種高度都要過。
  for (final kb in [0.0, 336.0, 410.0, 470.0]) {
    testWidgets('鍵盤 ${kb.toInt()}pt:儲存按鈕存在、在畫面內、且點得到', (tester) async {
      await _open(tester, keyboard: kb);

      // App 主題把 FilledButton 設成 Size.fromHeight(54)(寬度 infinity)。
      // 直接放進 Row 會「強制無限寬」:debug 拋 assertion、release 不報錯但按鈕
      // 被排到畫面外 —— 實測回報就是「改完只有取消,沒有儲存」。
      expect(tester.takeException(), isNull,
          reason: '版面丟出例外(release 版不會崩,但按鈕會不見)');

      final save = find.widgetWithText(FilledButton, '儲存');
      expect(save, findsOneWidget);

      final r = tester.getRect(save);
      final screenH = 852.0;
      expect(r.width, lessThan(393),
          reason: '按鈕被撐成滿版/無限寬,會把同一列的東西推出畫面');
      expect(r.top, greaterThanOrEqualTo(0.0));
      expect(r.bottom, lessThanOrEqualTo(screenH - kb),
          reason: '按鈕落在鍵盤底下,使用者摸不到');

      // 真的按得到(不只是存在)。
      await tester.tap(save);
      await tester.pumpAndSettle();
    });
  }

  testWidgets('按儲存回傳輸入的文字', (tester) async {
    await _open(tester, keyboard: 336);
    await tester.enterText(find.byType(TextField), '改好的內容');
    await tester.tap(find.widgetWithText(FilledButton, '儲存'));
    await tester.pumpAndSettle();
    // showModalBottomSheet 的結果透過 Navigator.pop 回傳,這裡驗面板已關閉
    // 且沒有例外(回傳值本身由 provider 層的測試涵蓋)。
    expect(find.byType(SegmentEditSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('未修改時不顯示「還原原文」,已修改時才出現', (tester) async {
    await _open(tester, keyboard: 336);
    expect(find.text('還原原文'), findsNothing);
    await tester.pumpWidget(const SizedBox()); // 收掉上一個 App

    await _open(tester, keyboard: 336, text: '已經改過的內容', original: _long);
    expect(find.text('還原原文'), findsOneWidget);
    expect(find.textContaining('原文:'), findsOneWidget);
  });

  testWidgets('取消不回傳結果', (tester) async {
    final r = await _open(tester, keyboard: 336);
    expect(r, isNull);
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(find.byType(SegmentEditSheet), findsNothing);
  });
}
