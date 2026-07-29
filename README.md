# 會議助理 · Flutter 跨平台客戶端

錄音 → 即時逐字稿 → 結構化摘要 → 可對會議內容問答的個人助理(RAG)。
iOS + Android 單一 Dart 碼庫。**所有 AI/ML 都在公司 server**,本 App 是瘦客戶端
(只負責錄音、UI、播放、呼叫 API)。架構背景見 [`HANDOFF-cross-platform.md`](HANDOFF-cross-platform.md)。

## 快速開始

```bash
flutter pub get
flutter run            # 預設為 Mock 模式,任意帳密即可登入、可跑完整流程
flutter test           # 單元測試(ThinkParser / 摘要解析)
```

- **Mock 模式(預設開啟)**:內建記憶體後端,無需 server 即可示範登入、會議清單、
  即時逐字稿、摘要串流、助理問答。

### 接自架 server(設定頁)

到 App 內「**設定**」關閉 Mock 後,可分別設定兩台 server:

| 欄位 | 位置 | 說明 |
|---|---|---|
| **語音辨識 Server(FastAPI)Base URL** | 設定 → 語音辨識 Server | 登入、會議管理、轉錄(`WS /transcribe/stream`) |
| **略過登入(開發用)** | 設定 → 連線模式 | 後端尚未做 auth 時直接進入 App |
| **直連 vLLM** | 設定 → AI 模型 | 開啟後聊天/摘要直接呼叫 vLLM |
| **vLLM Base URL** | 設定 → AI 模型 | 例如 `https://vllm.內網:8000/v1` |
| **API Key** | 設定 → AI 模型 | 存 **Keychain**;送出 `Authorization: Bearer <key>` |
| **模型名稱 (model)** | 設定 → AI 模型 | `/v1/chat/completions` 的 `model` 欄位 |

- **開發階段**(ASR=FastAPI、LLM=vLLM 分開跑):開「直連 vLLM」+ 填 URL/Key/model,
  聊天與摘要直接打 vLLM 的 `/v1/chat/completions`(OpenAI 相容,串流)。單場會議問答會把
  該場逐字稿塞進 system prompt 當上下文。
- **正式環境**:關掉「直連 vLLM」,聊天/摘要改走你的 FastAPI(由 server 端做 agentic RAG
  與跨會議檢索)。vLLM 的 API key 應放在 **FastAPI 端**,App 只連你的後端 —— 手機端存 key
  有被取出的風險,且 App 直連 vLLM 無法做跨會議 RAG。

## 架構

```
UI (features/)  ──watch──▶  Riverpod controllers (providers/)  ──▶  Backend 介面 (services/)
                                                                      ├─ HttpBackend  (REST + WebSocket + SSE)
                                                                      └─ MockBackend  (無 server demo)
錄音/播放:AudioRecorderService(record 16kHz PCM 串流)· AudioPlayerService(just_audio)
```

- **狀態管理**:Riverpod(`Notifier` / `AsyncNotifier` / `family`)。
- **路由**:go_router(依登入狀態自動導向)。
- **後端抽象**:`services/backend.dart` 定義介面;正式/示範以 `settings.useMock` 切換,
  切換時 `backendProvider` 自動重建。

### 目錄

| 路徑 | 說明 |
|---|---|
| `lib/models/` | 資料模型(Meeting、TranscriptSegment、MeetingSummary、ChatMessage…) |
| `lib/core/` | 設定、主題、網路原語(SSE 解析、`<think>` 串流過濾器)、Keychain 憑證儲存 |
| `lib/services/` | Backend 介面 + Http/Mock 實作、錄音、播放 |
| `lib/providers/` | Riverpod 控制器(auth、meetings、recording、summary、assistant、settings) |
| `lib/features/` | 各畫面(登入、會議清單、錄音、會議詳情、摘要、助理、設定) |
| `lib/widgets/` | 共用元件(逐字稿檢視、音量計、播放列、聊天氣泡) |

## 對應的 server API 契約(HANDOFF 第 6 節)

client 依下列契約呼叫;server 尚未實作時用 Mock 模式。

| 功能 | 端點 |
|---|---|
| 登入 | `POST /auth/token`(form-urlencoded,相容 FastAPI OAuth2PasswordRequestForm)→ JWT |
| 會議 | `GET /meetings` · `GET /meetings/{id}` · `POST /meetings` · `DELETE /meetings/{id}` |
| 逐字稿 | `GET /meetings/{id}/transcript` |
| 即時轉錄 | `WS /transcribe/stream`(上傳 16kHz PCM,收 `{text, is_final, speaker?}`) |
| 整檔轉錄 | `POST /meetings/{id}/audio`(multipart) |
| 摘要 | `POST /meetings/{id}/summarize` → **SSE** 串流 |
| 助理 | `POST /assistant/chat` → **SSE** 串流(server 端跑 agentic RAG) |

SSE 事件解析對純文字 delta 與 JSON(含 OpenAI 相容 `choices[].delta.content`)都相容,
`data: [DONE]` 或 `event: done` 作為結束訊號。

## 已實作的需求(HANDOFF 第 2 節)

- 前景/背景/鎖屏錄音(iOS `UIBackgroundModes: audio` + audio_session;Android 權限見下)。
- 即時逐字稿:WebSocket 邊錄邊出;暫定片段以淡色斜體、定稿後轉正。
- 說話者辨識:可開關、可**指定人數**(設定或錄音頁調整,附加到轉錄請求)。
- 摘要:固定結構(會議摘要 / 討論重點 / 決議 / 待辦[負責人+期限] / 後續追蹤),SSE 串流。
- 個人助理:SSE 串流對話、**滑動視窗 + 字元預算**避免爆 context、可**隱藏 `<think>`** 推理區塊。
- 錄音本地落地為 WAV(防斷線 + 播放)。

## 平台設定

- **iOS**:`ios/Runner/Info.plist` 已加 `NSMicrophoneUsageDescription` 與
  `UIBackgroundModes: audio` → 鎖屏/背景持續錄音(audio session 保活)。
- **Android**:`AndroidManifest.xml` 已加 `RECORD_AUDIO`、`INTERNET`、
  `FOREGROUND_SERVICE`、`FOREGROUND_SERVICE_MICROPHONE`、`POST_NOTIFICATIONS` 等;`minSdk = 24`。
  - **背景錄音前景服務**:錄音時啟動 `flutter_foreground_task` 的 microphone 型前景服務
    (帶常駐通知),讓 Android 9+ 在鎖屏/背景仍可收音;停止錄音即關閉。見
    `lib/services/recording_foreground_service.dart`(僅 Android 生效)。
  - **明文連線**:`usesCleartextTraffic="true"`,供內網/Tailscale 以 `http://` / `ws://` 測試;
    正式環境改用 HTTPS 後可移除。

### 待辦(follow-up)

- Token 刷新 / 401 自動導回登入。
- 團隊共享空間(HANDOFF 第 8 節待決策)。
- (選)錄音中螢幕常亮(wakelock)。
