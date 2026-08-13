import 'dart:io';

import 'package:flutter/services.dart';

/// 在耗時工作期間請求系統延後暫停 App(iOS background task assertion)。
///
/// 為什麼需要:上傳一小時的錄音(未壓縮約 110MB)可能要數分鐘。若期間 App 離開前景,
/// iOS 會很快暫停它 —— 上傳就中斷或看起來像「閃退到桌面」。宣告 background task 後,
/// 系統會給一段額外執行時間把工作做完。
///
/// Android 不需要:上傳在 Dart isolate 內進行,離開前景不會立即被暫停
/// (真正的長時間背景作業另由前景服務處理)。
class BackgroundTask {
  BackgroundTask._();

  static const MethodChannel _channel = MethodChannel('app/background_task');

  /// 在 [action] 執行期間保持 App 可繼續運作。
  ///
  /// 一定會結束 assertion(即使 action 丟出例外)—— 未結束的 assertion 會被系統
  /// 強制終止 App。
  static Future<T> run<T>(Future<T> Function() action) async {
    if (!Platform.isIOS) return action();
    Object? token;
    try {
      token = await _channel.invokeMethod<int>('begin');
    } catch (_) {
      // 取不到就照常執行,只是少了延長時間的保障。
    }
    try {
      return await action();
    } finally {
      if (token != null) {
        try {
          await _channel.invokeMethod<void>('end', {'token': token});
        } catch (_) {}
      }
    }
  }
}
