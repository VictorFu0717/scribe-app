import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meeting_assistant/app.dart';
import 'package:meeting_assistant/core/storage/token_storage.dart';
import 'package:meeting_assistant/models/auth_token.dart';
import 'package:meeting_assistant/providers/service_providers.dart';
import 'package:meeting_assistant/providers/settings_controller.dart';
import 'package:meeting_assistant/widgets/gradient_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 記憶體版 TokenStorage,避免測試碰到 flutter_secure_storage 的原生 channel。
class _FakeTokenStorage extends TokenStorage {
  AuthToken? _token;
  @override
  Future<AuthToken?> read() async => _token;
  @override
  Future<void> write(AuthToken token) async => _token = token;
  @override
  Future<void> clear() async => _token = null;
}

void main() {
  testWidgets('登入 → 會議清單(Mock 後端全流程)', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          tokenStorageProvider.overrideWithValue(_FakeTokenStorage()),
        ],
        child: const MeetingAssistantApp(),
      ),
    );

    // 啟動 → auth restore(無 token)→ 登入頁。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('登入'), findsWidgets);

    // 輸入帳密並登入。
    await tester.enterText(find.byType(TextFormField).first, 'demo');
    await tester.enterText(find.byType(TextFormField).last, 'pw');
    await tester.tap(find.widgetWithText(GradientButton, '登入'));

    // 等 mock login(350ms)+ 導向 + listMeetings(350ms)。
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    // 進到會議清單,顯示種子資料。
    expect(find.text('開始錄音'), findsOneWidget);
    expect(find.text('產品週會 — 第 27 週'), findsOneWidget);
  });
}
