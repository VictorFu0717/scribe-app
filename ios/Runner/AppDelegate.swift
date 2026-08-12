import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// 保留強引用,否則 channel 會被釋放而收不到呼叫。
  private var keepAwakeChannel: FlutterMethodChannel?
  private var incomingFileChannel: FlutterMethodChannel?
  private var audioConvertChannel: FlutterMethodChannel?

  /// 從其他 App 分享/開啟進來、等待 Dart 端取走的音檔路徑。
  /// 冷啟動時 Dart 尚未就緒,故先暫存,由 Dart 主動來取(見 lib/services/incoming_file.dart)。
  private var pendingIncomingFile: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// 非 UIScene 情境的接收路徑(保留作為後備)。
  ///
  /// 注意:本 App 走 UIScene 生命週期,分享進來的 URL **不會**經過這裡,
  /// 而是由 SceneDelegate 的 scene(_:openURLContexts:) 與 willConnectTo 收到 ——
  /// 先前只實作這個方法,導致在分享清單點了「會議助理」卻毫無反應。
  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if receiveIncomingFile(url) { return true }
    return super.application(app, open: url, options: options)
  }

  /// 收下分享進來的音檔(複製到快取後暫存路徑)。回傳是否成功接手。
  /// 由 SceneDelegate 於 UIScene 生命週期下呼叫。
  @discardableResult
  func receiveIncomingFile(_ url: URL) -> Bool {
    guard let copied = copyToCache(url) else { return false }
    pendingIncomingFile = copied
    // 主動通知 Dart(僅作為觸發訊號,實際路徑仍由 Dart 呼叫 take 取走,
    // 避免重複匯入)。冷啟動時 channel 尚未建立,此呼叫會被忽略,
    // 那種情況由 Dart 啟動後主動來取。
    incomingFileChannel?.invokeMethod("onIncomingFile", arguments: nil)
    return true
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

    // WAV → m4a(AAC):一小時 WAV 約 110MB,轉檔後約 9MB,才傳得出去。
    // 見 lib/services/audio_convert.dart。
    let convert = FlutterMethodChannel(
      name: "app/audio_convert", binaryMessenger: messenger)
    convert.setMethodCallHandler { call, result in
      guard call.method == "wavToM4a",
        let args = call.arguments as? [String: Any],
        let src = args["src"] as? String,
        let dst = args["dst"] as? String
      else {
        result(FlutterMethodNotImplemented)
        return
      }
      AppDelegate.exportToM4a(src: src, dst: dst, result: result)
    }
    audioConvertChannel = convert
  }

  /// 用 AVFoundation 把 WAV 轉成 m4a(AAC)。
  ///
  /// 用 AppleM4A preset:它會依原始取樣率/聲道自動選合適位元率 ——
  /// 實測 16kHz mono 的結果約為 WAV 的 1/12,不需要手動指定位元率。
  private static func exportToM4a(
    src: String, dst: String, result: @escaping FlutterResult
  ) {
    let srcURL = URL(fileURLWithPath: src)
    let dstURL = URL(fileURLWithPath: dst)
    try? FileManager.default.removeItem(at: dstURL) // 匯出目標必須不存在

    let asset = AVURLAsset(url: srcURL)
    guard
      let session = AVAssetExportSession(
        asset: asset, presetName: AVAssetExportPresetAppleM4A)
    else {
      result(false)
      return
    }
    session.outputURL = dstURL
    session.outputFileType = .m4a
    session.exportAsynchronously {
      // 回到主執行緒回覆 Flutter(MethodChannel 要求)。
      DispatchQueue.main.async {
        result(session.status == .completed)
      }
    }
  }
}
