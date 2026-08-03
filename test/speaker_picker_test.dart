import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meeting_assistant/widgets/speaker_count_picker.dart';

void main() {
  testWidgets('說話者人數選單:可捲動、不溢位(修 bottom overflow)', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showSpeakerCountPicker(context),
            child: const Text('open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 選項都在(2..8 + 自動),且沒有 RenderFlex overflow 例外。
    expect(find.text('自動偵測'), findsOneWidget);
    expect(find.text('8 人'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
