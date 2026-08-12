import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';

/// 選取一個手機上既有的音檔,回傳可讀取的本機路徑(取消回 null)。
///
/// **Android 自行以 SAF 實作**,不用 file_selector:
/// `file_selector_android` 的 `openFile()` 會把整個檔案讀成 bytes 再經
/// method channel 傳給 Dart(`XFile.fromData(file.bytes, …)`)—— 選一個上百 MB
/// 的錄音檔就會 OOM 閃退(實測)。自己走 `ACTION_OPEN_DOCUMENT` 並**串流複製**
/// 到 App 快取,只回傳路徑,記憶體用量與檔案大小無關。
///
/// iOS 沿用 file_selector:`file_selector_ios` 直接回傳路徑(`XFile(path)`),
/// 沒有這個問題。
class AudioFilePicker {
  AudioFilePicker._();

  static const MethodChannel _channel = MethodChannel('app/pick_audio');

  /// 支援的音檔格式(兩個平台的選取器都用這份清單)。
  static const _extensions = <String>[
    'wav', 'm4a', 'mp3', 'aac', 'aiff', 'caf', 'flac',
  ];

  static Future<String?> pick() async {
    if (Platform.isAndroid) {
      try {
        return await _channel.invokeMethod<String>('pick');
      } catch (_) {
        return null;
      }
    }

    // iOS:文件選取器(Files),而非音樂庫選取器 —— 後者需
    // NSAppleMusicUsageDescription 否則閃退,且是選歌不是選檔。
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: '音檔',
          extensions: _extensions,
          mimeTypes: ['audio/*'],
          uniformTypeIdentifiers: ['public.audio'],
        ),
      ],
    );
    return file?.path;
  }
}
