import 'dart:io';

import 'package:flutter/services.dart';

/// 把檔案存到手機(Android 的系統「另存新檔」對話框)。
///
/// 為什麼需要:Android 的分享選單只列出「可接收檔案的 App」,**沒有** iOS 那種
/// 內建的「儲存到檔案」。要存到手機必須走 SAF 的 `ACTION_CREATE_DOCUMENT`。
///
/// `file_selector` 雖有 `getSaveLocation()`,但 file_selector_android 並未實作
/// (只有 openFile / openFiles / getDirectoryPath),故自行以 MethodChannel 實作。
///
/// iOS 不需要:系統分享面板本身就有「儲存到檔案」,所以 [isSupported] 為 false,
/// UI 不顯示這個按鈕。
class SaveToDevice {
  SaveToDevice._();

  static const MethodChannel _channel = MethodChannel('app/save_file');

  /// 是否需要/支援此功能(僅 Android)。
  static bool get isSupported => Platform.isAndroid;

  /// 開啟系統「另存新檔」對話框,把 [path] 的內容存到使用者選擇的位置。
  ///
  /// 回傳 true 表示已存檔;使用者取消或失敗回 false。
  static Future<bool> save(
    String path, {
    required String fileName,
    required String mimeType,
  }) async {
    if (!isSupported || !File(path).existsSync()) return false;
    try {
      return await _channel.invokeMethod<bool>('save', {
            'src': path,
            'name': fileName,
            'mime': mimeType,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }
}
