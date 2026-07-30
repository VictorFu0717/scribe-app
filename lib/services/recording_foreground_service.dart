import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Android 背景錄音的前景服務包裝。
///
/// 為什麼需要:Android 9(API 28)起,App 進背景/鎖屏後**禁止存取麥克風**,
/// 除非有一個執行中、type=microphone 的前景服務(帶常駐通知)。錄音時啟動它,
/// 讓 App 程序在鎖屏後仍存活、麥克風不被切斷。
///
/// iOS 不需要(靠 Info.plist `UIBackgroundModes: audio` + 啟用中的 audio session
/// 就會在鎖屏後持續錄音),因此本服務所有方法在非 Android 平台皆為 no-op。
class RecordingForegroundService {
  RecordingForegroundService._();

  static bool get _isAndroid => Platform.isAndroid;
  static bool _inited = false;

  /// 在 App 啟動時呼叫一次(設定通知頻道與服務選項)。
  static void init() {
    if (!_isAndroid) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'recording_service',
        channelName: '會議錄音',
        channelDescription: '錄音進行中會顯示此通知,讓錄音在鎖屏/背景持續。',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false, // iOS 靠 audio background mode,不需通知
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        // 我們只需要服務「存活」以保住麥克風權限,不需週期性 Dart callback。
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
        allowWifiLock: true, // 錄音期間保持 WiFi 無線電清醒(對付積極省電機型)
      ),
    );
    _inited = true;
  }

  /// 開始錄音時啟動前景服務(Android)。回傳是否成功。
  static Future<bool> start({required String title}) async {
    if (!_isAndroid) return true;
    if (!_inited) init();

    // Android 13+ 需要通知權限才能顯示前景服務通知。
    try {
      final perm = await FlutterForegroundTask.checkNotificationPermission();
      if (perm != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
    } catch (_) {}

    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
      final result = await FlutterForegroundTask.startService(
        serviceTypes: [ForegroundServiceTypes.microphone],
        notificationTitle: '會議助理・錄音中',
        notificationText: title,
      );
      return result is ServiceRequestSuccess;
    } catch (_) {
      // 前景服務啟動失敗不阻斷錄音(前景時仍可錄;只是鎖屏可能中斷)。
      return false;
    }
  }

  /// 停止錄音時關閉前景服務。
  static Future<void> stop() async {
    if (!_isAndroid) return;
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
    } catch (_) {}
  }
}
