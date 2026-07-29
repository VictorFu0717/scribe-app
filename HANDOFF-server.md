# scribe server 調整需求(給 server 端 Claude Code 的施作規格)

> 這份文件由「會議助理 App(Flutter 端)」這邊產出,貼給 scribe server 端的 Claude Code。
> 目的:讓 server 從目前「即時 ASR + 單場問答」原型,逐步長成 App 需要的完整後端。
> **App 已經照最終規格做好、在等 server 跟上;請依本文件的契約與順序實作。**

---

## 0. 架構前提(先讀)

- 這是一個**瘦客戶端**架構:**所有 AI/ML 與資料儲存都在 server(你)**;App 只負責錄音、UI、播放、呼叫 API。
- 使用者在台灣,一律**繁體中文(台灣用語)**輸出(你目前的 OpenCC `s2twp` 很好,保留)。
- **不要破壞**你現有、且前端測試已通過的東西:
  - 雙模型即時 ASR(FunASR 預覽 + VAD 斷句 + Qwen3-ASR 定稿)
  - OpenCC 簡→繁
  - `WS /ws/asr` 的訊息協定(見第 3 節,App 會去配合你這個協定,你**不用改訊息格式**)
  - `GET /health`

---

## 1. 現況盤點(你目前有的)

| 端點 | 狀態 |
|---|---|
| `WS /ws/asr` | ✅ 即時轉錄(累積式 `partial`/`final`,可 `config` 開 diarization) |
| `POST /meeting/chat` | ✅ 單場問答(stateless,body 帶 `transcript`) |
| `GET /health` | ✅ |

**缺少(App 需要)**:資料儲存(會議/逐字稿/摘要)、會議 CRUD、摘要端點、跨會議問答(RAG)、登入。
**本質問題**:server 目前**無狀態**——不存會議、沒有 `meeting_id` 概念。這是所有後續功能(尤其 RAG)的最大缺口。

---

## 2. 施作順序(依相依關係,由下而上)

RAG 不能第一步做,它要先有「存起來的會議」才有東西可檢索。請照這個順序:

```
① 儲存層(meetings + transcripts + summaries)   ← 一切的地基
      ↓
② ASR 定稿後寫入儲存(WS 帶 meeting_id)
      ↓
③ 會議 CRUD 端點        → App 會議清單/詳情可用
      ↓
④ 摘要端點(SSE)        → App 摘要頁可用
      ↓
⑤ 助理問答端點(SSE,單場)→ App 助理(單場)可用
      ↓
⑥ RAG(embedding+向量庫+跨會議問答)→ App 助理(全部會議)可用
      ↓
⑦ 登入 + diarization 指定人數(收尾/選配)
```

**每一步做完,App 對應的畫面就能直接使用(App UI 已就緒)。**

---

## 3. WebSocket 轉錄(維持現狀,只做小增補)

**你不用改訊息格式**;App 端會配合你「累積式 `partial`/`final`」的協定。你只需要做兩件事:

1. **`config` 訊息多吃兩個欄位**(可選):
   ```jsonc
   {"type":"config", "diarization": true, "speaker_count": 3, "meeting_id": "<id>"}
   ```
   - `meeting_id`:把這場轉錄關聯到某個已建立的會議(第 5 節 `POST /meetings` 產生)。
   - `speaker_count`:期望的說話者人數(見第 7 節;做不到可先忽略)。
2. **收到 `{"type":"end"}` 定稿完成後**:把 `final` 的 `text` 與 `segments` **寫入儲存**(第 4 節),存在對應的 `meeting_id` 底下;並更新該會議的 `duration_sec`、`status="ready"`。

> App 端會自己把你的 `partial.committed`/`tentative`/`segments` 轉成畫面。你維持現有輸出即可。

---

## 4. 儲存層(① 地基)

用什麼都行(SQLite / Postgres 皆可;要接 RAG 建議 **Postgres + pgvector**,一魚兩吃)。需要能存三種東西,且**都掛在 `meeting_id` 底下、且屬於某個 `user_id`**(多租戶,RAG 檢索要靠它隔離):

- **meeting**:`id, user_id, title, created_at, duration_sec, status, has_summary`
- **transcript**:某 meeting 的逐字稿片段列表 `[{text, speaker?, start_ms?, end_ms?}]`
- **summary**:某 meeting 的結構化摘要(見第 6 節的 JSON 形狀)

`status` 列舉值(App 有對應顯示):`recording | uploading | transcribing | processing | ready | error`。

---

## 5. 會議 CRUD(③)

App 會直接呼叫以下路徑(這些就是 App 內建的契約,實作成這樣 App 免改即可用)。
所有回應 **JSON**;時間一律 **ISO 8601 字串**(如 `2026-07-23T10:30:00Z`)。

### `GET /meetings`
列出目前使用者的會議。回傳陣列或 `{"items":[...]}` 皆可:
```json
{ "items": [
  { "id": "m001", "title": "產品週會", "created_at": "2026-07-22T02:00:00Z",
    "duration_sec": 2580, "status": "ready", "has_summary": true, "audio_url": null }
]}
```

### `GET /meetings/{id}`
回傳單一 meeting(欄位同上)。

### `POST /meetings`
建立會議(App 開始錄音時呼叫)。body `{"title":"..."}` → 回傳新 meeting(`status` 可為 `"recording"`)。

### `DELETE /meetings/{id}`
刪除;回 200/204 即可。

### `GET /meetings/{id}/transcript`
```json
{ "segments": [
  { "id": "s1", "text": "我們先確認里程碑。", "speaker": "說話者 1",
    "is_final": true, "start_ms": 0, "end_ms": 3200 }
]}
```
- `speaker`:字串(如 `"說話者 1"`)或整數(App 會把整數 n 顯示成「說話者 n+1」);沒開 diarization 給 `null`。
- 回傳陣列或 `{"segments":[...]}` 皆可。

### `GET /meetings/{id}/summary`
沒有摘要時回 **404**;有的話回第 6 節的 summary JSON。

---

## 6. 摘要端點(④,SSE 串流)

### `POST /meetings/{id}/summarize`
- App 送:`{"language":"zh-Hant"}`(header 帶 `Authorization` 若有)。
- server 內部:用 `meeting_id` 取出該場逐字稿 → 丟給你的對話 LLM(Qwen3.6-27B)產生摘要 → **SSE 串流**。長逐字稿請用 **map-reduce**(分段摘要再合併)。
- **回傳格式(SSE)**:先**串流文字 delta**(邊產邊顯示),最後**送一個結構化 JSON** 再 `[DONE]`:
  ```
  data: {"delta": "本次會議"}
  data: {"delta": "確認了..."}
  ...
  data: {"overview":"...","key_points":["..."],"decisions":["..."],"action_items":[{"task":"...","owner":"小林","due":"本週五"}],"follow_ups":["..."]}
  data: [DONE]
  ```
- **固定結構(繁中)**,App 會渲染成分區卡片:
  - `overview` 會議摘要(字串)
  - `key_points` 討論重點(字串陣列)
  - `decisions` 決議事項(字串陣列)
  - `action_items` 待辦事項(物件陣列:`task` 必填,`owner`/`due` 選填)
  - `follow_ups` 後續追蹤(字串陣列)
- 作法建議:prompt 要求 LLM 以固定 Markdown 段落輸出並串流;串完後 server 端把 Markdown 解析成上面的 JSON 再送出。這樣同時有「串流體感」與「結構化卡片」。

> 註:App 會自動隱藏 `<think>...</think>` 區塊,所以推理模型開不開 thinking 都行。

---

## 7. 助理問答端點(⑤ 單場 →⑥ 跨會議 RAG)

### `POST /assistant/chat`(SSE 串流)—— 取代 stateless 的 `/meeting/chat`
- App 送:
  ```json
  { "messages": [ {"role":"user","content":"這場的決議是什麼?"} ],
    "meeting_id": "m001",         // 有 = 單場;省略/null = 跨全部會議
    "language": "zh-Hant" }
  ```
  - `messages` 是完整對話歷史(App 已做 token 預算/滑動視窗,你直接用)。
- server 行為:
  - **有 `meeting_id`(⑤)**:用該場逐字稿當 grounding 回答(等同你現在的 `/meeting/chat`,只是逐字稿改由 server 用 id 自己取,不再由 client 帶)。
  - **無 `meeting_id`(⑥ RAG)**:對「該使用者的所有會議」做檢索式問答(見下)。
- **回傳格式(SSE)**:`data: {"delta":"..."}` 逐段,最後 `data: [DONE]`。
  (App 也吃 OpenAI 原生 `{"choices":[{"delta":{"content":"..."}}]}`,兩種擇一。)

### ⑥ RAG 設計(這步較大,可最後做)
建議技術棧(對齊原始交接文件):
1. **索引(寫入時)**:逐字稿 final、摘要產生後 → 切塊(逐字稿按說話者輪次或 ~300 token+重疊;摘要每段)→ `bge-m3` 產 embedding → 存向量庫(**pgvector** 或 Qdrant),每塊帶 metadata:`{user_id, meeting_id, type: transcript|summary, speaker, start_ms, created_at}`。
2. **檢索+生成(查詢時)**:問題 → embedding → 向量庫 top-k(**務必用 `user_id` filter 做多租戶隔離**)→(可選 rerank)→ 檢索片段 + 對話歷史 → 你的 chat LLM → SSE 串流。
3. **agentic RAG(進階)**:若沿用你既有那套,把 `retrieve_meetings(query, filters)` 註冊成 vLLM 的 tool(需 `--enable-auto-tool-choice --tool-call-parser`),讓 LLM 自己決定何時/多輪檢索。
4.(加分)回應可附**出處**(哪幾場會議/片段),App 之後能顯示來源。

---

## 8. 登入 + diarization 指定人數(⑦,選配/收尾)

### `POST /auth/token`(OAuth2 password,form-urlencoded)
- App 送(`application/x-www-form-urlencoded`):`grant_type=password&username=<帳號>&password=<密碼>`
- 回傳:`{"access_token":"...","token_type":"bearer","expires_in":43200}`(`refresh_token` 選填)。
- 之後所有端點檢查 `Authorization: Bearer <token>`;WS 可在連線 header 或第一個訊息帶 token。
- **開發期**可先寬鬆(任意帳密發 token),App 端也有「略過登入」開關,不做這步也能先跑。

### diarization 指定人數
- App 會在 `config` 帶 `speaker_count`。你目前 `diarize.py` 是 cosine 門檻自動分群;若要支援指定 K,可改成把該場所有語者向量做**指定群數的聚類**(如 agglomerative 到 K 群)。做不到可先忽略此欄位(不致命)。

---

## 9. 驗收:對接是否成功

每步做完可這樣驗:
- ③ 之後:App 會議清單能列出、點得進去、看得到逐字稿。
- ④ 之後:App 摘要頁按「產生摘要」會串流出文字並顯示五大分區卡片。
- ⑤ 之後:App 會議詳情的「助理」分頁能問這場會議。
- ⑥ 之後:App 首頁的「個人助理」(不限單場)能跨會議問答。

App 端連線設定:關閉 Mock、填你的 server URL、開發期開「略過登入」。WS 轉錄 App 會對接你的 `/ws/asr`。

---

## 10. 一句話總結給你(server 端 Claude)

**優先把「無狀態」變「有狀態」**——先做儲存層(①②),再把會議 CRUD③、摘要④、助理⑤ 依 App 契約補齊,最後上 RAG⑥。訊息格式與路徑請嚴格照本文件,App 端不需要再改就能對接。ASR 那條(`/ws/asr`)維持現狀,只加 `meeting_id` 關聯與定稿後寫入儲存即可。
