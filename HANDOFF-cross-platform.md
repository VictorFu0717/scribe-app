# 會議記錄 App — 跨平台(iOS + Android)架構交接文件

> 這份文件把 iOS 原型階段驗證出的需求 + 我們討論定案的**生產架構**濃縮下來,
> 作為「新的跨平台專案(Flutter/RN + 公司 server)」的起點。把它放進新 repo 當 spec/README。
> 產出日期:2026-07(iOS 原型:MeetingMinutes,Swift/SwiftUI)。

## 0. 一句話架構

**Server 擁有全部 AI/ML(用 Python 寫一次,接回公司既有的 faster-whisper GPU + agentic RAG);iOS 與 Android 都是瘦客戶端(只負責錄音、UI、播放、呼叫 API),可用 Flutter/React Native 一次寫兩端。**

原因:on-device ML 全是 Apple 專屬(WhisperKit/CoreML/ANE、Foundation Models、MLX、NLContextualEmbedding、SpeakerKit、Swift),**無法移植到 Android**;放 server 才能一套邏輯、雙端共用、品質一致、低規手機也能用。公司內部 → 資料進公司 server 即屬內網私密。

## 1. 產品是什麼(已由 iOS 原型驗證)

會議錄音 App:**錄音 → 即時逐字稿 → 結構化摘要 → 可對會議內容問答的個人助理(RAG)**。使用者在台灣,輸出**繁體中文(台灣用語)**。

## 2. 已驗證的需求 / UX(直接搬到新版)

- **錄音**:前景/背景/鎖屏都要能持續收音;錄音檔可本地播放。
- **即時逐字稿**:邊錄邊出字;用 **VAD(語音活動偵測)在停頓處分段**,而不是固定秒數(固定秒數會切在句中、體感差)。
- **說話者辨識(diarization)**:可開關;逐字稿標「說話者 1/2…」;需**指定人數選項**(自動常把相近音色併成一人,能手動指定最可靠)。
- **摘要**:固定結構(繁中):會議摘要 / 討論重點 / 決議事項 / 待辦事項(負責人+期限)/ 後續追蹤;長逐字稿要 **map-reduce**;**串流逐字產出**(不要等整段跑完)。
- **個人助理**:與 LLM **串流對話**;**agentic RAG** 檢索過去會議(逐字稿 + 摘要都要索引);對話要有 **token 預算/滑動視窗**避免爆 context。
- **推理模型**:要能隱藏 `<think>` 區塊只顯示答案。

## 3. 目標架構

```
 iOS App ┐                                   ┌─ ASR(faster-whisper, GPU;串流 + 批次)
 (thin)  ├──錄音串流/上傳、SSE/WebSocket──▶  Server ─┼─ 摘要(LLM,map-reduce,SSE 串流)
 Android ┘        HTTPS + JWT                        ├─ 嵌入 + 向量庫 + 檢索(bge/e5 + Qdrant/pgvector)
 (thin)                                              └─ Agent 編排 + 工具(既有 Python agentic RAG)
```

| 層 | 位置 |
|---|---|
| 錄音 / 播放 / UI / 本地暫存 | 手機(雙端) |
| ASR、摘要、嵌入、向量庫、RAG、Agent、Auth | **Server(Python)** |

## 4. Server 職責 + 建議技術棧

- **框架**:FastAPI(async、SSE/WebSocket 友善)。
- **ASR**:faster-whisper(GPU)—— 公司已在用。支援「串流(即時)」與「整檔上傳後轉」兩種。
- **Diarization**:pyannote(server 端 GPU)。
- **摘要 / 聊天生成**:vLLM(OpenAI 相容;開 `--enable-auto-tool-choice --tool-call-parser` 供 agent 用)。
- **嵌入**:`bge-m3` 或 `multilingual-e5`(GPU;中文檢索遠優於裝置端 NLContextualEmbedding)。
- **向量庫**:Qdrant 或 pgvector。
- **Agent**:沿用公司既有 agentic RAG;工具(retrieve_meetings 等)在 server 執行。
- **Auth / 多租戶**:JWT/OAuth;每人自己的會議(可留「共享空間」擴充)。
- **資料治理**:音訊留存/刪除政策;逐字稿與向量的生命週期。

## 5. Client 職責 + 建議框架

- **建議 Flutter**(單一 Dart 碼庫、iOS+Android、audio/背景/WebSocket 外掛成熟)。React Native 亦可(JS 生態);KMP 若想 UI 各自原生。
- 職責:錄音(+ 本地暫存以防斷線)、串流/上傳音訊、顯示即時逐字稿、串流顯示摘要與聊天、播放、Auth token、背景錄音(平台外掛)。
- **不做任何 ML**。

## 6. API 契約草案(iOS 先接、Android 共用)

- `POST /auth/token` — 公司帳號登入 → JWT。
- **會議**:`GET /meetings`、`GET /meetings/{id}`、`POST /meetings`、`DELETE /meetings/{id}`。
- **轉錄**(擇一或都提供):
  - `WS /transcribe/stream` — 上傳 16kHz PCM、收 `{text, isFinal, speaker?}`(即時)。
  - `POST /meetings/{id}/audio` — 整檔上傳 → 非同步轉錄 → 逐字稿。
- **摘要**:`POST /meetings/{id}/summarize` → **SSE 串流**結構化摘要。
- **個人助理**:`POST /assistant/chat`(**SSE 串流**)—— body 帶對話歷史;server 端跑 agentic RAG(工具在 server 執行),串流回答。
- **索引**:server 在逐字稿/摘要產生後**自動**建索引(客戶端不參與)。

## 7. iOS 原型 → 帶得走 vs 要重做

- **帶得走(需求/UX/契約)**:上面第 2 節全部;摘要的提示詞與結構;VAD 分段邏輯的參數直覺;RAG 該索引逐字稿+摘要;token 預算;串流 UX。
- **重做(換到 server)**:所有 ML(WhisperKit→faster-whisper、FM/vLLM、NLEmbedding→bge/e5、SpeakerKit→pyannote、on-device 向量庫→Qdrant)。Swift UI → Flutter/RN。

## 8. 待決策

- 即時串流轉錄 vs 整檔上傳後轉(或兩者)。
- 會議資料:純個人 vs 團隊共享空間。
- 音訊是否留存於 server(還是轉完即刪)。
- 客戶端框架:Flutter / RN / KMP。

## 9. 下一步

1. 在**新資料夾**開新專案(Flutter/RN),把本文件放進去當 spec。
2. 先定 server 的 API 契約(第 6 節)+ 立一個最小 FastAPI(接上既有 faster-whisper + agentic RAG)。
3. Flutter 端做 MVP:登入 → 錄音上傳 → 顯示逐字稿 → 摘要(SSE)→ 助理問答(SSE)。
4. iOS 原型(此 repo)可當「需求對照 / UX 參考」,不再加深其 on-device 投資。
