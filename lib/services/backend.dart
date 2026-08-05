import '../models/auth_token.dart';
import '../models/chat_message.dart';
import '../models/meeting.dart';
import '../models/summary.dart';
import '../models/transcript_segment.dart';
import '../models/transcription_config.dart';

/// 摘要 SSE 串流的一個片段。
///
/// server 可串流 markdown 文字(`textDelta`,邊產邊顯示),並在結尾附上
/// 結構化 `summary`(可選)。`done=true` 代表串流結束。
class SummaryChunk {
  const SummaryChunk({this.textDelta, this.summary, this.done = false});
  final String? textDelta;
  final MeetingSummary? summary;
  final bool done;
}

/// 助理聊天 SSE 串流的一個 token 片段。
class ChatChunk {
  const ChatChunk({this.textDelta, this.done = false});
  final String? textDelta;
  final bool done;
}

/// 留檔翻譯 SSE 串流的一個片段(對應 scribe `POST /meetings/{id}/translate`)。
///
/// server 逐塊回傳 `{"delta":"..."}`,結束送 `[DONE]`;翻完會存檔,
/// 之後可用 `getTranslation` 重取。`error` 非 null 代表 server 端出錯。
class TranslateChunk {
  const TranslateChunk({this.textDelta, this.done = false, this.error});
  final String? textDelta;
  final bool done;
  final String? error;
}

/// 一次即時轉錄連線(對應 `WS /transcribe/stream`)。
///
/// 即時轉錄的一次「累積快照」。
///
/// server(scribe `/ws/asr`)是累積式推送:每次回目前**全部**已定稿片段
/// (`finalSegments`,其文字/說話者會被就地升級)+ 當前預覽(`partial`,灰字)。
/// 因此這裡用整份快照,UI 每次直接替換,天然支援「就地升級」。
class TranscriptUpdate {
  const TranscriptUpdate({this.finalSegments = const [], this.partial});

  /// 目前所有已定稿片段(可能被後續升級覆蓋)。
  final List<TranscriptSegment> finalSegments;

  /// 當前正在進行、尚未定稿的預覽片段(灰字);無則為 null。
  final TranscriptSegment? partial;
}

/// 一次即時轉錄連線(對應 scribe `WS /ws/asr`)。
///
/// 上傳 16kHz PCM、接收累積式 `TranscriptUpdate`。
abstract class TranscriptionSession {
  /// server 回傳的逐字稿累積快照流。
  Stream<TranscriptUpdate> get updates;

  /// 送出一段 16-bit PCM 音訊(little-endian, mono, 16kHz)。
  void sendAudio(List<int> pcm16);

  /// 通知 server 錄音結束、等待收尾(final)並關閉連線。
  Future<void> stop();
}

/// 後端抽象:所有 AI/ML 都在 server(交接文件第 0 節)。
/// `HttpBackend` 接真後端;`MockBackend` 供無 server 時 demo。
abstract class Backend {
  // ── Auth ──
  Future<AuthToken> login({required String username, required String password});
  Future<AuthToken> register(
      {required String username, required String password});

  // ── Meetings CRUD ──
  Future<List<Meeting>> listMeetings();
  Future<Meeting> getMeeting(String id);
  Future<Meeting> createMeeting({required String title});
  Future<void> deleteMeeting(String id);

  // ── 逐字稿 / 摘要讀取 ──
  Future<List<TranscriptSegment>> getTranscript(String meetingId);
  Future<MeetingSummary?> getSummary(String meetingId);

  // ── 轉錄 ──
  /// 開啟即時轉錄連線(WebSocket)。
  TranscriptionSession openTranscription({
    required String meetingId,
    required TranscriptionConfig config,
  });

  /// 整檔上傳後非同步轉錄。
  Future<Meeting> uploadAudio(
    String meetingId,
    String filePath, {
    required TranscriptionConfig config,
  });

  // ── 串流生成 ──
  /// 產生結構化摘要(SSE 串流)。
  Stream<SummaryChunk> summarize(String meetingId);

  /// 個人助理問答(SSE 串流);server 端跑 agentic RAG。
  Stream<ChatChunk> chat({
    required List<ChatMessage> messages,
    String? meetingScopeId,
  });

  // ── 翻譯 ──
  /// 整篇逐字稿的高品質留檔翻譯(SSE 串流,server 端 LLM;翻完存檔)。
  ///
  /// 即時雙語字幕走裝置內翻譯(見 `OnDeviceTranslatorService`),不打 server。
  Stream<TranslateChunk> translate(String meetingId, {required String target});

  /// 取回已存檔的翻譯;未翻譯過回 null。
  Future<String?> getTranslation(String meetingId, {required String target});

  // ── 播放輔助 ──
  /// 將相對路徑或完整 URL 解析為可播放的 Uri。
  Uri resolveUri(String pathOrUrl);

  /// 播放/下載音檔時所需的認證標頭。
  Future<Map<String, String>> authHeaders();

  /// 釋放資源(如 http client)。
  void dispose() {}
}
