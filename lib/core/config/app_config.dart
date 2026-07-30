/// 全域預設值與編譯期設定。
///
/// 執行期可覆寫的項目(base URL、mock 開關、diarization 預設)存在 Settings
/// (見 `settings_controller.dart`);此處只放預設與不變的常數。
class AppConfig {
  AppConfig._();

  /// scribe server base URL 預設值(部署走 Tailscale;見 server README)。
  /// 可用 `--dart-define=API_BASE_URL=http://...` 覆寫,或在設定頁修改。
  static const String defaultApiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://100.68.0.81:8005',
  );

  /// 是否預設使用內建 mock 後端(無 server 也能 demo 全流程)。
  /// 預設連真 server;要離線示範可在設定頁開 Mock,或 `--dart-define=USE_MOCK=true`。
  static const bool defaultUseMock =
      bool.fromEnvironment('USE_MOCK', defaultValue: false);

  // ── 音訊擷取格式(faster-whisper 串流需求) ──
  static const int sampleRate = 16000;
  static const int numChannels = 1;

  /// 每次送往 WS 的 PCM 緩衝目標大小(bytes)。約 100ms @16kHz/16bit/mono。
  static const int streamChunkBytes = 3200;

  // ── 個人助理 context 管理(token 預算 / 滑動視窗) ──
  /// 對話歷史保留的最大訊息數(滑動視窗)。
  static const int assistantMaxMessages = 24;

  /// 送往 server 的歷史字元預算(粗略近似 token,避免爆 context)。
  static const int assistantCharBudget = 12000;

  static const String appName = '會議助理';
}
