import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// 保留強引用,否則 channel 會被釋放而收不到呼叫。
  private var keepAwakeChannel: FlutterMethodChannel?
  private var incomingFileChannel: FlutterMethodChannel?

  /// 從其他 App 分享/開啟進來、等待 Dart 端取走的音檔路徑。
  /// 冷啟動時 Dart 尚未就緒,故先暫存,由 Dart 主動來取(見 lib/services/incoming_file.dart)。
  private var pendingIncomingFile: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// 使用者從語音備忘錄等 App 分享音檔過來時觸發(冷啟動與已在執行中都會走這裡)。
  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if let copied = copyToCache(url) {
      pendingIncomingFile = copied
      return true
    }
    return super.application(app, open: url, options: options)
  }

  /// 把來源檔複製到 App 快取。
  ///
  /// 必須複製:分享進來的 URL 多為 security-scoped(或位於 Inbox),存取權限是
  /// 一次性的,直接保留路徑之後會讀不到。
  private func copyToCache(_ url: URL) -> String? {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }

    let fm = FileManager.default
    guard let cacheDir = fm.urls(for: .cachesDirectory, in: .userDomainMask).first
    else { return nil }
    let inbox = cacheDir.appendingPathComponent("incoming", isDirectory: true)
    try? fm.createDirectory(at: inbox, withIntermediateDirectories: true)

    // 保留原始檔名(會用來當會議標題),同名則加上時間戳避免覆蓋。
    var dest = inbox.appendingPathComponent(url.lastPathComponent)
    if fm.fileExists(atPath: dest.path) {
      let stamp = String(Int(Date().timeIntervalSince1970))
      let base = url.deletingPathExtension().lastPathComponent
      let ext = url.pathExtension
      dest = inbox.appendingPathComponent("\(base)_\(stamp).\(ext)")
    }

    do {
      try fm.copyItem(at: url, to: dest)
      return dest.path
    } catch {
      return nil
    }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()

    // 螢幕常亮(錄音期間)。見 lib/services/keep_awake.dart:自行實作以取代 wakelock_plus。
    let keepAwake = FlutterMethodChannel(
      name: "app/keep_awake", binaryMessenger: messenger)
    keepAwake.setMethodCallHandler { call, result in
      guard call.method == "setKeepAwake" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let enable = (call.arguments as? [String: Any])?["enable"] as? Bool ?? false
      UIApplication.shared.isIdleTimerDisabled = enable
      result(nil)
    }
    keepAwakeChannel = keepAwake

    // 分享進來的音檔:Dart 端於啟動與回到前景時來取。
    let incoming = FlutterMethodChannel(
      name: "app/incoming_file", binaryMessenger: messenger)
    incoming.setMethodCallHandler { [weak self] call, result in
      guard call.method == "take" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let path = self?.pendingIncomingFile
      self?.pendingIncomingFile = nil // 取走即清空,避免重複匯入同一檔
      result(path)
    }
    incomingFileChannel = incoming
  }
}
