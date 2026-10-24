import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meeting_assistant/core/theme/app_theme.dart';
import 'package:meeting_assistant/models/meeting_diagram.dart';
import 'package:meeting_assistant/widgets/diagram_card.dart';
import 'package:meeting_assistant/widgets/diagram_view.dart';

const _diagram = MeetingDiagram(
  kind: 'flow',
  code: 'flowchart TD\n  n1["需求確認"] --> n2["上線"]',
);

/// 推進畫面。不用 pumpAndSettle:載入中的轉圈圈是無限動畫,永遠不會 settle。
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('全螢幕的圖不能被包在捲動/縮放容器裡', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () => openDiagramFullScreen(ctx, _diagram),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await _settle(tester);

    final view =
        find.byWidgetPredicate((w) => w is DiagramView && w.interactive);
    expect(view, findsOneWidget);
    // 實測回報的 bug:先前包在 SingleChildScrollView + InteractiveViewer 裡,
    // WebView 被撐成整張圖那麼高、又吃掉所有手勢 —— 外層捲不動、裡面沒東西
    // 可捲,放大後只看得到上半部。捲動與縮放必須交給 WebView 自己處理。
    expect(
        find.ancestor(of: view, matching: find.byType(SingleChildScrollView)),
        findsNothing);
    expect(find.ancestor(of: view, matching: find.byType(InteractiveViewer)),
        findsNothing);
  });

  testWidgets('點縮圖會開啟全螢幕', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(
        body: SingleChildScrollView(child: DiagramCard(diagram: _diagram)),
      ),
    ));
    await _settle(tester);

    // 縮圖的 WebView 被 IgnorePointer 包住,點擊要靠外層 opaque 的
    // GestureDetector 接住(InkWell 在這種情況下收不到點擊)。
    final thumb =
        find.byWidgetPredicate((w) => w is DiagramView && !w.interactive);
    expect(thumb, findsOneWidget);
    await tester.tap(thumb, warnIfMissed: false);
    await _settle(tester);

    expect(find.byWidgetPredicate((w) => w is DiagramView && w.interactive),
        findsOneWidget);
  });

  test('縮圖高度上限放寬到 560(420 時 8 個節點的流程圖字只剩約 8px)', () {
    expect(const DiagramView(diagram: _diagram).maxHeight, 560);
  });
}
