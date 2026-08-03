import Flutter
import UIKit

// 用經典 UIWindow/AppDelegate 生命週期(非 UIScene)。
// 原因:Flutter 新版 SceneDelegate 生命週期在 iOS 26 上,從後台移除後重開觸發
// scene 重建時,引擎的 VSyncClient 初始化會 SIGSEGV 閃退。改回經典生命週期後,
// 不再有 scene 重連路徑,問題消失。
@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
