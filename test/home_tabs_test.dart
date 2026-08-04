import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
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
  setUpAll(() async => initializeDateFormatting('zh_TW', null));

  testWidgets('底部三分頁:會議記錄 / AI 助理 / 設定,可切換', (tester) async {
    // 維持預設寬度、加高視窗,讓設定頁底部的「登出」在已建範圍內(ListView 懶載入)。
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({'settings.use_mock': true});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        tokenStorageProvider.overrideWithValue(_AuthedTokenStorage()),
      ],
      child: const MeetingAssistantApp(),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));

    NavigationBar nav() =>
        tester.widget<NavigationBar>(find.byType(NavigationBar));

    // 有底部導覽,預設在「會議記錄」。
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(nav().selectedIndex, 0);
    expect(find.text('AI 助理'), findsWidgets);

    // 切到 AI 助理(未選時圖示 auto_awesome_outlined)。
    await tester.tap(find.byIcon(Icons.auto_awesome_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(nav().selectedIndex, 1);

    // 切到設定 → 有登出。
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(nav().selectedIndex, 2);
    expect(find.text('登出'), findsOneWidget);
  });
}
