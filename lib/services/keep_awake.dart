import 'package:flutter/services.dart';

/// 螢幕常亮(錄音期間避免自動鎖屏中斷背景錄音)。
///
/// 自行以 MethodChannel 實作而不用 wakelock_plus,原因:
/// - wakelock_plus 1.6.0~1.7.0 的 Android 端 `Wakelock.kt` 使用 root-package import
///   (`import IsEnabledMessage`),在 Flutter 內建 Kotlin(Built-in Kotlin)下編譯失敗。
/// - 能編譯的 1.5.x 又鎖 win32 ^5,與 share_plus 13.x(win32 ^6)相衝。
///
/// 原生實作各只需一個 API:
/// - iOS: `UIApplication.shared.isIdleTimerDisabled`
/// - Android: window flag `FLAG_KEEP_SCREEN_ON`
class KeepAwake {
  KeepAwake._();

  static const MethodChannel _channel = MethodChannel('app/keep_awake');

  /// 開啟螢幕常亮。
  static Future<void> enable() => _set(true);

  /// 關閉螢幕常亮(回復系統自動鎖屏)。
  static Future<void> disable() => _set(false);

  static Future<void> _set(bool enable) async {
    try {
      await _channel.invokeMethod<void>('setKeepAwake', {'enable': enable});
    } catch (_) {
      // 平台未實作或呼叫失敗時靜默忽略——螢幕常亮只是輔助,不該影響錄音本身。
    }
  }
}
