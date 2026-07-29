# scribe-app · 會議助理(Flutter,iOS/Android)

錄音 → 即時逐字稿 → 結構化摘要 → 可對會議內容問答的個人助理(RAG)。
iOS + Android 單一 Dart 碼庫。**瘦客戶端**:所有 AI/ML(ASR、LLM、RAG)都在
[scribe server](https://github.com/VictorFu0717/scribe),App 只負責錄音、UI、播放,
並**只連 server 這一個對外入口**(不直連任何模型服務)。

架構背景見 [`HANDOFF-cross-platform.md`](HANDOFF-cross-platform.md);
與 server 的 API 契約見 [`HANDOFF-server.md`](HANDOFF-server.md)。

> Flutter 套件名為 `meeting_assistant`;GitHub repo 為 `scribe-app`,與 server 端 `scribe` 對應。

## 快速開始

```bash
flutter pub get
flutter run     # 預設 Mock 模式,任意帳密即可登入、離線跑完整流程
flutter test    # 單元 / widget 測試(見「測試」)
```

- **Mock 模式(預設)**:內建記憶體後端,無需 server 即可示範登入、會議清單、
  即時逐字稿、摘要串流、助理問答、刪除。

### 接 scribe server(設定頁)

App 內「**設定**」→ 關閉 Mock 後,只需填**一個** server 位址:

| 項目 | 位置 | 說明 |
|---|---|---|
| **使用 Mock 模式** | 設定 → 連線 | 關閉後改連真 server |
| **略過登入(開發用)** | 設定 → 連線 | server 尚未啟用 auth 時直接進入 App |
| **Server 位址** | 設定 → 連線 | scribe 的唯一入口,如 `http://192.168.x.x:8005` |
| **即時串流轉錄** | 設定 → 轉錄 | 開:WS 邊錄邊出字;關:錄完整檔上傳轉錄 |
| **說話者辨識 / 指定人數** | 設定 → 轉錄 | diarization 開關與人數 |

逐字稿、摘要、AI 助理全部由 scribe **內部**轉發到 vLLM/Ollama —— App 不需要、
也不應該知道模型服務的位址或金鑰。

### 用 Tailscale + http 測試(開發)

把手機與 server 加入同一個 Tailscale tailnet,Server 位址填 server 的 `100.x.y.z:8005` 即可
(手機走行動網路也能連)。App 網路走 `dart:io`,iOS 明文 `http://`/`ws://` 免額外設定;
Android 已設 `usesCleartextTraffic="true"`。正式對外請改用 HTTPS。

## 架構

```
UI (features/)  ──watch──▶  Riverpod controllers (providers/)  ──▶  Backend 介面 (services/)
                                                                      ├─ HttpBackend  (REST + WebSocket + SSE → scribe)
                                                                      └─ MockBackend  (無 server demo)
錄音/播放:AudioRecorderService(record 16kHz PCM 串流)· AudioPlayerService(just_audio)
背景錄音:RecordingForegroundService(Android microphone 前景服務;iOS 靠 audio background mode)
```

- **狀態管理**:Riverpod(`Notifier` / `AsyncNotifier` / `family`)。
- **路由**:go_router(依登入狀態自動導向)。
- **後端抽象**:`services/backend.dart` 定義介面;以 `settings.useMock` 在
  `HttpBackend` / `MockBackend` 間切換,切換時 `backendProvider` 自動重建。

### 目錄

| 路徑 | 說明 |
|---|---|
| `lib/models/` | 資料模型(Meeting、TranscriptSegment、MeetingSummary、ChatMessage…) |
| `lib/core/` | 設定、主題、網路原語(SSE 解析、`<think>` 串流過濾器)、Keychain JWT 儲存 |
| `lib/services/` | Backend 介面 + Http/Mock 實作、錄音、播放、背景前景服務 |
| `lib/providers/` | Riverpod 控制器(auth、meetings、recording、summary、assistant、settings) |
| `lib/features/` | 各畫面(登入、會議清單、錄音、會議詳情、摘要、助理、設定) |
| `lib/widgets/` | 共用元件(逐字稿檢視、音量波形、播放列、聊天氣泡、漸層元件) |

## 與 scribe server 的 API 契約

App 呼叫下列端點(皆為 scribe 的單一 port);已對齊 server 實作,細節見
[`HANDOFF-server.md`](HANDOFF-server.md)。

| 功能 | 端點 |
|---|---|
| 登入(選配) | `POST /auth/token`(form-urlencoded,OAuth2);dev 可「略過登入」 |
| 會議 | `GET /meetings` · `GET /meetings/{id}` · `POST /meetings` · `DELETE /meetings/{id}` |
| 逐字稿 | `GET /meetings/{id}/transcript` |
| 即時轉錄 | `WS /ws/asr`(見下) |
| 整檔轉錄 | `POST /meetings/{id}/audio`(multipart:`file` + `diarization` 表單欄位) |
| 摘要 | `POST /meetings/{id}/summarize` → **SSE**(文字 delta → 結構化 JSON → `[DONE]`) |
| 助理 | `POST /assistant/chat` → **SSE**(server 端 agentic RAG;帶 `meeting_id` 為單場,否則跨會議) |

**`WS /ws/asr` 協定**(累積式,對齊 scribe):

- Client → Server:先送 `{"type":"config","diarization":bool,"speaker_count"?:int,"meeting_id":id}`,
  接著 16kHz mono PCM16 二進位音框,結束送 `{"type":"end"}`。
- Server → Client:`{"type":"partial","segments":[{speaker,text}],"tentative":".."}`(邊錄邊更新)、
  最後 `{"type":"final","segments":[..]}`。App 以「累積快照」呈現,天然支援句子被就地升級
  (預覽字 → 定稿 → 補說話者)。

SSE 解析同時相容純文字 delta、`{"delta":".."}` 與 OpenAI `choices[].delta.content`,
以 `data: [DONE]` 或 `event: done` 作結束訊號;助理回覆中的 `<think>…</think>` 會在 client 隱藏。

## 已實作功能

- **錄音**:前景/背景/鎖屏持續錄音;本地落地為 WAV(防斷線 + 播放)。
  - iOS:`UIBackgroundModes: audio` + audio session 保活。
  - Android:錄音時啟動 microphone 型前景服務(常駐通知),鎖屏/背景不斷線。
- **即時逐字稿**:WS 邊錄邊出;暫定片段淡色斜體,定稿後轉正、可標說話者。
- **說話者辨識**:可開關、可指定人數。
- **摘要**:固定結構(會議摘要 / 討論重點 / 決議 / 待辦[負責人+期限] / 後續追蹤),SSE 串流。
- **個人助理**:SSE 串流對話、滑動視窗 + 字元預算避免爆 context、隱藏 `<think>`;
  單場(會議詳情內)與跨會議(首頁助理)兩種範圍。
- **會議管理**:清單、詳情(逐字稿/摘要/助理三分頁 + 播放列)、**刪除**
  (詳情頁垃圾桶或清單滑動;連帶刪除 server 的逐字稿/摘要/RAG 索引)。

## 平台設定

- **iOS**:`ios/Runner/Info.plist` 已加 `NSMicrophoneUsageDescription` 與
  `UIBackgroundModes: audio`。
- **Android**:`AndroidManifest.xml` 已加 `RECORD_AUDIO`、`INTERNET`、
  `FOREGROUND_SERVICE`、`FOREGROUND_SERVICE_MICROPHONE`、`POST_NOTIFICATIONS`;`minSdk = 24`;
  宣告 `flutter_foreground_task` 的 `ForegroundService`(`foregroundServiceType="microphone"`);
  `usesCleartextTraffic="true"`(內網/Tailscale http 測試用,正式改 HTTPS 可移除)。
  背景錄音邏輯見 `lib/services/recording_foreground_service.dart`(僅 Android 生效)。

## 測試

```bash
flutter analyze && flutter test
```

- `widget_test.dart` — `<think>` 串流分離、摘要 JSON 解析
- `ws_asr_adapter_test.dart` — 對接假 `/ws/asr`:累積式 partial/final → 快照
- `server_contract_test.dart` — 鎖定對 scribe 實際回傳形狀的解析(會議/逐字稿/摘要 SSE/助理/上傳/刪除)
- `delete_flow_test.dart` — 會議詳情刪除鈕端到端流程
- `app_flow_test.dart` — 登入 → 會議清單

## 待辦(follow-up)

- Token 刷新 / 401 自動導回登入。
- 團隊共享空間(HANDOFF 第 8 節待決策)。
- (選)錄音中螢幕常亮(wakelock)、助理答案顯示檢索出處。
