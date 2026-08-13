import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// 保留強引用,否則 channel 會被釋放而收不到呼叫。
  private var keepAwakeChannel: FlutterMethodChannel?
  private var incomingFileChannel: FlutterMethodChannel?
  private var audioConvertChannel: FlutterMethodChannel?
  private var backgroundTaskChannel: FlutterMethodChannel?

  /// 進行中的 background task assertion(見 lib/services/background_task.dart)。
  /// 上傳大檔可能耗時數分鐘,期間 App 若離開前景會被 iOS 暫停而中斷上傳。
  private var backgroundTasks: [Int: UIBackgroundTaskIdentifier] = [:]
  private var nextBackgroundTaskToken = 1

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

    // WAV → m4a(AAC 64kbps):一小時 WAV 約 110MB,轉檔後約 28MB,才傳得出去。
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
      // 位元率由 Dart 端指定,兩平台一致(見 lib/services/audio_convert.dart)。
      let bitRate = (args["bitRate"] as? Int) ?? 64_000
      AppDelegate.exportToM4a(src: src, dst: dst, bitRate: bitRate, result: result)
    }
    audioConvertChannel = convert

    // 延長執行時間(上傳大檔期間避免被系統暫停)。
    let background = FlutterMethodChannel(
      name: "app/background_task", binaryMessenger: messenger)
    background.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      switch call.method {
      case "begin":
        let token = self.nextBackgroundTaskToken
        self.nextBackgroundTaskToken += 1
        let id = UIApplication.shared.beginBackgroundTask(withName: "upload") {
          // 系統時間用盡:必須自行結束,否則 App 會被強制終止。
          self.endBackgroundTask(token)
        }
        if id == .invalid {
          result(nil)
        } else {
          self.backgroundTasks[token] = id
          result(token)
        }
      case "end":
        if let token = (call.arguments as? [String: Any])?["token"] as? Int {
          self.endBackgroundTask(token)
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    backgroundTaskChannel = background
  }

  private func endBackgroundTask(_ token: Int) {
    guard let id = backgroundTasks.removeValue(forKey: token) else { return }
    UIApplication.shared.endBackgroundTask(id)
  }

  /// 用 AVFoundation 把 WAV 轉成 m4a(AAC),**明確指定位元率**。
  ///
  /// 不用 AVAssetExportSession + AppleM4A preset:那個 preset 的位元率由系統決定、
  /// 無法控制,實測同款編碼器的自動值僅約 21kbps。研究指出 16kbps 級別的壓縮會使
  /// ASR 的 WER 相對劣化約 12.6%,而本機檔案會用於「斷線後重新轉錄」——
  /// 那正是最需要準確度的場合。故改用 AVAssetReader/Writer 固定 64kbps
  /// (與 Android 一致;16kHz 單聲道語音為 4:1 壓縮,一小時約 28MB 仍便於傳送)。
  private static func exportToM4a(
    src: String, dst: String, bitRate: Int, result: @escaping FlutterResult
  ) {
    let srcURL = URL(fileURLWithPath: src)
    let dstURL = URL(fileURLWithPath: dst)
    try? FileManager.default.removeItem(at: dstURL)

    let asset = AVURLAsset(url: srcURL)
    // 取來源的取樣率/聲道數以維持不變(用 AVAudioFile 讀,比從
    // CMFormatDescription 取更直接 —— 後者是 CoreFoundation 型別,轉型會被
    // Swift 視為恆成立而編譯失敗)。
    guard let track = asset.tracks(withMediaType: .audio).first,
      let srcFormat = try? AVAudioFile(forReading: srcURL).fileFormat
    else {
      result(false)
      return
    }

    do {
      let reader = try AVAssetReader(asset: asset)
      let readerOutput = AVAssetReaderTrackOutput(
        track: track,
        outputSettings: [
          AVFormatIDKey: kAudioFormatLinearPCM,
          AVLinearPCMBitDepthKey: 16,
          AVLinearPCMIsFloatKey: false,
          AVLinearPCMIsBigEndianKey: false,
          AVLinearPCMIsNonInterleaved: false,
        ])
      reader.add(readerOutput)

      let writer = try AVAssetWriter(outputURL: dstURL, fileType: .m4a)
      // 維持來源的取樣率與聲道數(本 App 錄音為 16kHz mono),只改編碼與位元率。
      let writerInput = AVAssetWriterInput(
        mediaType: .audio,
        outputSettings: [
          AVFormatIDKey: kAudioFormatMPEG4AAC,
          AVSampleRateKey: srcFormat.sampleRate,
          AVNumberOfChannelsKey: Int(srcFormat.channelCount),
          AVEncoderBitRateKey: bitRate,
        ])
      writerInput.expectsMediaDataInRealTime = false
      writer.add(writerInput)

      guard reader.startReading(), writer.startWriting() else {
        result(false)
        return
      }

      let queue = DispatchQueue(label: "app.audio.convert")
      writerInput.requestMediaDataWhenReady(on: queue) {
        while writerInput.isReadyForMoreMediaData {
          guard let sample = readerOutput.copyNextSampleBuffer() else {
            writerInput.markAsFinished()
            writer.finishWriting {
              let ok = writer.status == .completed && reader.status == .completed
              // 回到主執行緒回覆 Flutter(MethodChannel 要求)。
              DispatchQueue.main.async { result(ok) }
            }
            return
          }
          if !writerInput.append(sample) {
            writerInput.markAsFinished()
            writer.cancelWriting()
            DispatchQueue.main.async { result(false) }
            return
          }
        }
      }
    } catch {
      result(false)
    }
  }
}
