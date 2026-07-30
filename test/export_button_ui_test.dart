import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meeting_assistant/app.dart';
import 'package:meeting_assistant/core/storage/token_storage.dart';
import 'package:meeting_assistant/models/auth_token.dart';
import 'package:meeting_assistant/providers/service_providers.dart';
import 'package:meeting_assistant/providers/settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _AuthedTokenStorage extends TokenStorage {
  final _t = AuthToken(accessToken: 'x');
  @override
  Future<AuthToken?> read() async => _t;
  @override
  Future<void> write(AuthToken token) async {}
  @override
  Future<void> clear() async {}
}

void main() {
  testWidgets('會議詳情:逐字稿與摘要分頁都有「匯出 .txt」按鈕', (tester) async {
    SharedPreferences.setMockInitialValues({'settings.use_mock': true});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        tokenStorageProvider.overrideWithValue(_AuthedTokenStorage()),
      ],
      child: const MeetingAssistantApp(),
    ));

    // 到會議清單 → 進第一場(mock 種子,有逐字稿與摘要)。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('產品週會 — 第 27 週'));
    // 等 meetingProvider(350ms)+ transcriptProvider(350ms)串接載入完成。
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    // 逐字稿分頁(預設)應有匯出按鈕。
    expect(find.text('匯出逐字稿 .txt'), findsOneWidget);

    // 切到摘要分頁 → 應有匯出摘要按鈕。
    await tester.tap(find.widgetWithText(Tab, '摘要'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1)); // 等摘要載入(getSummary 350ms)
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('匯出摘要 .txt'), findsOneWidget);
  });
}
