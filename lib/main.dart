import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'providers/settings_controller.dart';
import 'providers/translation_models_controller.dart';
import 'services/audio_session_config.dart';
import 'services/recording_foreground_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 繁中(台灣)日期格式。
  await initializeDateFormatting('zh_TW', null);

  // 預設用播放設定(走擴音);錄音時會切到 playAndRecord,停止後切回。
  await AudioSessions.playback();

  // Android 背景錄音前景服務(設定通知頻道 / 選項;iOS 為 no-op)。
  RecordingForegroundService.init();

  final prefs = await SharedPreferences.getInstance();

  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
    ],
  );

  // 背景預先備妥中/英翻譯模型(各約 30MB),避免開會當下才下載而前幾句沒有譯文。
  // 刻意不 await:失敗只是回到「用到才下載」,不該影響 App 啟動。
  //
  // 放在 main() 而非 App widget 的 initState:widget 測試會直接 pumpWidget 建立
  // App,若在 initState 觸發,ML Kit 的 method channel 在測試環境不會回應,
  // 逾時計時器會殘留而讓測試失敗(A Timer is still pending…)。測試不經過 main()。
  container.read(translationModelsProvider.notifier).preloadDefaults();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const MeetingAssistantApp(),
    ),
  );
}
