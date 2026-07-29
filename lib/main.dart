import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'providers/settings_controller.dart';
import 'services/recording_foreground_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 繁中(台灣)日期格式。
  await initializeDateFormatting('zh_TW', null);

  // 音訊 session:錄音 + 播放,支援背景(iOS 需 Info.plist audio background mode)。
  await _configureAudioSession();

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

Future<void> _configureAudioSession() async {
  try {
    final session = await AudioSession.instance;
    await session.configure(AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
      avAudioSessionCategoryOptions:
          AVAudioSessionCategoryOptions.allowBluetooth |
              AVAudioSessionCategoryOptions.defaultToSpeaker,
      avAudioSessionMode: AVAudioSessionMode.spokenAudio,
      androidAudioAttributes: const AndroidAudioAttributes(
        contentType: AndroidAudioContentType.speech,
        usage: AndroidAudioUsage.voiceCommunication,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
    ));
  } catch (_) {
    // 音訊 session 設定失敗不阻斷啟動。
  }
}
