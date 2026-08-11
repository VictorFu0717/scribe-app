import 'package:flutter/services.dart';

/// 接收「從其他 App 分享/開啟」進來的音檔(iOS 語音備忘錄、LINE 語音、郵件附件…)。
///
/// 為什麼需要:iPhone「語音備忘錄」的錄音存在它自己的 App 容器,**不在「檔案」App**,
/// 所以我們的文件選擇器看不到。註冊成可接收音檔後,使用者可從語音備忘錄按分享
/// 直接送進本 App。
///
/// 自行以 MethodChannel 實作而不用第三方 plugin:功能單純(取一個檔案路徑),
/// 而本專案已多次因 plugin 的原生編譯問題受阻,自己實作更可控。
///
/// 原生端會把來源檔**複製到 App 快取**再回傳路徑 —— iOS 的 security-scoped URL
/// 與 Android 的 content:// 權限都可能是一次性的,不複製之後就讀不到。
class IncomingFile {
  IncomingFile._();

  static const MethodChannel _channel = MethodChannel('app/incoming_file');

  /// 取走待處理的分享檔案路徑(取走後原生端會清空);沒有則回 null。
  ///
  /// App 冷啟動(由分享動作喚起)與從背景返回時都要呼叫 —— 兩種情況原生端的
  /// 進入點不同,但都會把路徑暫存起來等這裡取走。
  static Future<String?> take() async {
    try {
      return await _channel.invokeMethod<String>('take');
    } catch (_) {
      return null; // 平台未實作或呼叫失敗時忽略,不影響 App 其他功能。
    }
  }
}
