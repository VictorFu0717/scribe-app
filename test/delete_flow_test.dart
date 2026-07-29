import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meeting_assistant/app.dart';
import 'package:meeting_assistant/core/storage/token_storage.dart';
import 'package:meeting_assistant/models/auth_token.dart';
import 'package:meeting_assistant/providers/service_providers.dart';
import 'package:meeting_assistant/providers/settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 一開始就已登入(略過登入頁),直接進會議清單。
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
  testWidgets('會議詳情刪除鈕:確認後從清單移除(Mock 後端)', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        tokenStorageProvider.overrideWithValue(_AuthedTokenStorage()),
      ],
      child: const MeetingAssistantApp(),
    ));

    // 啟動 → auth restore → 會議清單(mock 種子資料)。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('產品週會 — 第 27 週'), findsOneWidget);

    // 進入該會議詳情。
    await tester.tap(find.text('產品週會 — 第 27 週'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // 詳情頁有刪除鈕。
    final deleteBtn = find.byTooltip('刪除會議');
    expect(deleteBtn, findsOneWidget);

    // 點刪除 → 出現確認對話框。
    await tester.tap(deleteBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.widgetWithText(FilledButton, '刪除'), findsOneWidget);

    // 確認刪除。
    await tester.tap(find.widgetWithText(FilledButton, '刪除'));
    await tester.pump(); // 開始刪除
    await tester.pump(const Duration(milliseconds: 300)); // mock delete
    await tester.pump(const Duration(milliseconds: 500)); // 返回 + 清單重新載入
    await tester.pump(const Duration(milliseconds: 500));

    // 回到清單,該會議已消失,另一場仍在。
    expect(find.text('產品週會 — 第 27 週'), findsNothing);
    expect(find.text('客戶需求訪談 — 台中廠'), findsOneWidget);
  });
}
