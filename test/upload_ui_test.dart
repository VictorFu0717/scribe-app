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

  testWidgets('會議清單有「上傳音檔」入口', (tester) async {
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

    // 清單頁的上傳音檔入口(匯入現有錄音檔)。
    expect(find.byTooltip('上傳音檔'), findsOneWidget);

    // 進錄音頁仍正常(不再有整檔上傳模式選擇器)。
    await tester.tap(find.text('開始錄音'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('點擊開始錄音'), findsOneWidget);
  });
}
