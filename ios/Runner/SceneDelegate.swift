import Flutter
import UIKit

/// UIScene 生命週期下的場景代理。
///
/// 分享進來的音檔(語音備忘錄等)在 UIScene 模式下**不會**走
/// `application(_:open:options:)`,而是:
/// - App 已在執行:`scene(_:openURLContexts:)`
/// - 由分享動作冷啟動:`scene(_:willConnectTo:options:)` 的 `connectionOptions.urlContexts`
///
/// 先前只實作了 AppDelegate 的版本,所以在分享清單點「會議助理」毫無反應。
/// `@objc(SceneDelegate)` 固定 ObjC 執行期名稱,讓 Info.plist 的
/// UISceneDelegateClassName 可直接寫 `SceneDelegate`,不依賴 $(PRODUCT_MODULE_NAME)
/// 於 Info.plist 的變數展開。
@objc(SceneDelegate)
class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    // 必須先讓 Flutter 建立畫面,再處理 URL。
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    handleIncoming(connectionOptions.urlContexts)
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    super.scene(scene, openURLContexts: URLContexts)
    handleIncoming(URLContexts)
  }

  private func handleIncoming(_ contexts: Set<UIOpenURLContext>) {
    guard let url = contexts.first?.url,
      let appDelegate = UIApplication.shared.delegate as? AppDelegate
    else { return }
    // 交給 AppDelegate 暫存 —— MethodChannel 建在那裡,Dart 端會來取。
    appDelegate.receiveIncomingFile(url)
  }
}
