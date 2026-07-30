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

/// 未登入狀態:read() 回 null(不碰原生 keychain)。
class _EmptyTokenStorage extends TokenStorage {
  @override
  Future<AuthToken?> read() async => null;
  @override
  Future<void> write(AuthToken token) async {}
  @override
  Future<void> clear() async {}
}

void main() {
  testWidgets('登入頁有註冊按鈕,可進入註冊頁', (tester) async {
    SharedPreferences.setMockInitialValues({'settings.use_mock': true});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        tokenStorageProvider.overrideWithValue(_EmptyTokenStorage()),
      ],
      child: const MeetingAssistantApp(),
    ));

    // 未登入 → 登入頁。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.widgetWithText(GradientButton, '登入'), findsOneWidget);
    expect(find.text('註冊'), findsOneWidget);

    // 點註冊 → 註冊頁。
    await tester.tap(find.text('註冊'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('建立帳號'), findsOneWidget);
    expect(find.widgetWithText(GradientButton, '註冊並登入'), findsOneWidget);
  });

  testWidgets('未登入也能從登入頁進設定頁', (tester) async {
    SharedPreferences.setMockInitialValues({'settings.use_mock': true});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        tokenStorageProvider.overrideWithValue(_EmptyTokenStorage()),
      ],
      child: const MeetingAssistantApp(),
    ));

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // 登入頁的「設定」按鈕(Mock 模式頁尾;測試視窗較小需先捲入可視範圍)。
    await tester.ensureVisible(find.text('設定'));
    await tester.pump();
    await tester.tap(find.text('設定'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // 應真的到設定頁(而非被導回登入)。
    expect(find.text('使用 Mock 模式'), findsOneWidget);
  });
}
