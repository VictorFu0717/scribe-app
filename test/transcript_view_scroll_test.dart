import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meeting_assistant/core/theme/app_theme.dart';
import 'package:meeting_assistant/models/transcript_segment.dart';
import 'package:meeting_assistant/widgets/transcript_view.dart';

List<TranscriptSegment> build(int n, {String? overrideAt, int at = 0}) => [
      for (var i = 0; i < n; i++)
        TranscriptSegment(
          id: 's$i',
          text: (overrideAt != null && i == at)
              ? overrideAt
              : '第 $i 段的逐字稿內容,長度大概是一句話這樣。',
          isFinal: true,
          startMs: i * 5000,
        ),
    ];

void main() {
  testWidgets('片段內容變了,捲動位置要留在原處(不能跳回最上面)', (tester) async {
    tester.view.physicalSize = const Size(393 * 3, 852 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    Widget app(List<TranscriptSegment> segs) => MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: TranscriptView(segments: segs, onEdit: (_, __) {}),
          ),
        );

    await tester.pumpWidget(app(build(60)));
    await tester.pumpAndSettle();

    // 捲到中間某處。
    await tester.drag(find.byType(ListView), const Offset(0, -1500));
    await tester.pumpAndSettle();
    final offsetBefore =
        tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels;
    expect(offsetBefore, greaterThan(500), reason: '前提:確實捲下去了');

    // 改掉其中一段的文字(等同使用者編輯後的重建)。
    await tester.pumpWidget(app(build(60, overrideAt: '我改過的內容', at: 3)));
    await tester.pumpAndSettle();

    final offsetAfter =
        tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels;
    expect(offsetAfter, closeTo(offsetBefore, 40),
        reason: '捲動位置被重設 → 使用者改完一段就被丟回第一行');
  });
}
