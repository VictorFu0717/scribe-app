import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'providers/settings_controller.dart';
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

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const MeetingAssistantApp(),
    ),
  );
}
