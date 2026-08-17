import 'dart:async';

import '../models/auth_token.dart';
import '../models/chat_message.dart';
import '../models/meeting.dart';
import '../models/summary.dart';
import '../models/transcript_segment.dart';
import '../models/transcription_config.dart';
import 'backend.dart';

/// 記憶體內 mock 後端 —— 無 server 也能 demo 完整流程。
/// 正式接後端時在設定頁關閉 mock(或 `--dart-define=USE_MOCK=false`)。
class MockBackend implements Backend {
  final Map<String, Meeting> _meetings = {};
  final Map<String, List<TranscriptSegment>> _transcripts = {};
  final Map<String, MeetingSummary> _summaries = {};
  int _seq = 0;

  MockBackend() {
    _seed();
  }

  String _nextId() => 'm${(++_seq).toString().padLeft(3, '0')}';

  void _seed() {
    final now = DateTime.now();
    final m1 = Meeting(
      id: _nextId(),
      title: '產品週會 — 第 27 週',
      createdAt: now.subtract(const Duration(days: 1, hours: 2)),
      durationSec: 43 * 60,
      status: MeetingStatus.ready,
      hasSummary: true,
    );
    final m2 = Meeting(
      id: _nextId(),
      title: '客戶需求訪談 — 台中廠',
      createdAt: now.subtract(const Duration(days: 4)),
      durationSec: 58 * 60,
      status: MeetingStatus.ready,
      hasSummary: true,
    );
    for (final m in [m1, m2]) {
      _meetings[m.id] = m;
    }
    _transcripts[m1.id] = [
      const TranscriptSegment(
          id: 's1',
          text: '這週我們先確認跨平台版本的里程碑。',
          isFinal: true,
          speaker: '說話者 1'),
      const TranscriptSegment(
          id: 's2',
          text: 'iOS 原型已經驗證完需求,接下來重點是 server 端的 API 契約。',
          isFinal: true,
          speaker: '說話者 2'),
      const TranscriptSegment(
          id: 's3',
          text: '我負責先立一個最小的 FastAPI,接上既有的 faster-whisper。',
          isFinal: true,
          speaker: '說話者 1'),
    ];
    _summaries[m1.id] = const MeetingSummary(
      overview: '本次週會確認跨平台(iOS + Android)會議記錄 App 的生產架構與里程碑,'
          '定調所有 AI/ML 集中於公司 server,雙端以 Flutter 開發瘦客戶端。',
      keyPoints: [
        'iOS 原型已完成需求與 UX 驗證,可作為需求對照。',
        'on-device ML 為 Apple 專屬,無法移植 Android,故一律移至 server。',
        '優先定義 server API 契約,再做 Flutter MVP。',
      ],
      decisions: [
        '客戶端採用 Flutter(單一 Dart 碼庫)。',
        'ASR 沿用公司既有 faster-whisper(GPU)。',
      ],
      actionItems: [
        ActionItem(task: '建立最小 FastAPI 並接上 faster-whisper', owner: '小林', due: '本週五'),
        ActionItem(task: '完成 Flutter 登入 → 錄音上傳 → 逐字稿 MVP', owner: '阿德', due: '下週三'),
      ],
      followUps: ['下週會議確認 diarization(pyannote)整合進度。'],
    );
    _transcripts[m2.id] = [
      const TranscriptSegment(
          id: 't1', text: '我們現場的會議室常常收訊不穩,離線也要能錄。', isFinal: true, speaker: '說話者 1'),
    ];
    _summaries[m2.id] = const MeetingSummary(
      overview: '客戶關注離線錄音穩定性與逐字稿正確率,期望支援多人會議的說話者辨識。',
      keyPoints: ['現場網路不穩,需本地暫存防斷線。', '多人會議需能指定說話者人數。'],
      decisions: ['錄音一律先落地本地檔,再背景上傳。'],
      actionItems: [ActionItem(task: '評估背景上傳重試機制', owner: '阿德')],
      followUps: ['安排一次現場實測。'],
    );
  }

  Future<T> _delay<T>(T value, [int ms = 350]) =>
      Future.delayed(Duration(milliseconds: ms), () => value);

  @override
  Future<AuthToken> login({
    required String username,
    required String password,
  }) =>
      _delay(AuthToken(
        accessToken: 'mock-token-$username',
        expiresAt: DateTime.now().add(const Duration(hours: 12)),
      ));

  @override
  Future<AuthToken> register({
    required String username,
    required String password,
  }) =>
      login(username: username, password: password);

  @override
  Future<List<Meeting>> listMeetings() {
    final list = _meetings.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return _delay(list);
  }

  @override
  Future<Meeting> getMeeting(String id) =>
      _delay(_meetings[id] ?? (throw StateError('not found')));

  @override
  Future<Meeting> createMeeting({required String title}) {
    final m = Meeting(
      id: _nextId(),
      title: title,
      createdAt: DateTime.now(),
      status: MeetingStatus.recording,
    );
    _meetings[m.id] = m;
    _transcripts[m.id] = [];
    return _delay(m, 150);
  }

  @override
  Future<void> deleteMeeting(String id) {
    _meetings.remove(id);
    _transcripts.remove(id);
    _summaries.remove(id);
    return _delay(null, 150);
  }

  @override
  Future<List<TranscriptSegment>> getTranscript(String meetingId) =>
      _delay(List.of(_transcripts[meetingId] ?? const []));

  @override
  Future<MeetingSummary?> getSummary(String meetingId) =>
      _delay(_summaries[meetingId]);

  @override
  TranscriptionSession openTranscription({
    required String meetingId,
    required TranscriptionConfig config,
  }) =>
      _MockTranscriptionSession(
        config: config,
        onFinal: (seg) => (_transcripts[meetingId] ??= []).add(seg),
      );

  @override
  Future<Meeting> uploadAudio(
    String meetingId,
    String filePath, {
    required TranscriptionConfig config,
  }) async {
    final m = _meetings[meetingId];
    if (m == null) throw StateError('not found');
    final updated = m.copyWith(status: MeetingStatus.transcribing);
    _meetings[meetingId] = updated;
    // 模擬非同步轉錄完成:2 秒後 ready 並產生逐字稿(供輪詢/匯入流程 demo)。
    Future.delayed(const Duration(seconds: 2), () {
      _meetings[meetingId] =
          updated.copyWith(status: MeetingStatus.ready, durationSec: 90);
      _transcripts[meetingId] = const [
        TranscriptSegment(id: 's0', text: '(整檔上傳)這是上傳音檔轉出的逐字稿示範。', isFinal: true),
        TranscriptSegment(id: 's1', text: '實際內容會由 server 的 Qwen3-ASR 定稿產生。', isFinal: true),
      ];
    });
    return _delay(updated, 500);
  }

  @override
  Stream<SummaryChunk> summarize(String meetingId) async* {
    final existing = _summaries[meetingId];
    final summary = existing ??
        const MeetingSummary(
          overview: '這是一段由 mock 產生的會議摘要,示範 SSE 串流逐字輸出的效果。',
          keyPoints: ['重點一:確認架構方向。', '重點二:分工與時程。'],
          decisions: ['採用 server 集中式 ML。'],
          actionItems: [ActionItem(task: '建立 API 契約', owner: '小林', due: '本週')],
          followUps: ['下次會議追蹤進度。'],
        );
    // 逐字串流 overview,再送出結構化結果。
    final text = summary.overview;
    for (var i = 0; i < text.length; i += 2) {
      await Future.delayed(const Duration(milliseconds: 40));
      yield SummaryChunk(
          textDelta: text.substring(i, (i + 2).clamp(0, text.length)));
    }
    await Future.delayed(const Duration(milliseconds: 200));
    _summaries[meetingId] = summary;
    final m = _meetings[meetingId];
    if (m != null) _meetings[meetingId] = m.copyWith(hasSummary: true);
    yield SummaryChunk(summary: summary, done: true);
  }

  @override
  Stream<ChatChunk> chat({
    required List<ChatMessage> messages,
    String? meetingScopeId,
  }) async* {
    final q = messages.lastWhere((m) => m.isUser,
        orElse: () => ChatMessage(role: ChatRole.user, content: '')).content;
    final answer =
        '<think>使用者想了解「$q」。我從已索引的會議逐字稿與摘要中檢索相關段落再作答。</think>'
        '根據過去會議紀錄,關於「$q」的重點是:團隊已定調將所有 AI/ML 放在公司 server,'
        '客戶端用 Flutter 一次開發雙端。若需要,我可以幫你列出相關的決議事項與待辦。';
    for (var i = 0; i < answer.length; i += 3) {
      await Future.delayed(const Duration(milliseconds: 25));
      yield ChatChunk(
          textDelta: answer.substring(i, (i + 3).clamp(0, answer.length)));
    }
    yield const ChatChunk(done: true);
  }

  // ── 翻譯 ──
  /// Mock 翻譯:把逐字稿逐行加上目標語言標記後串流回傳(僅供 UI 流程示範)。
  final Map<String, String> _translations = {};

  @override
  Stream<TranslateChunk> translate(String meetingId,
      {required String target}) async* {
    final segs = await getTranscript(meetingId);
    final lines = segs
        .where((s) => s.text.trim().isNotEmpty)
        .map((s) => s.speaker != null
            ? '${s.speaker}：[$target] ${s.text}'
            : '[$target] ${s.text}')
        .join('\n');
    final text = lines.isEmpty ? '[$target] (無逐字稿)' : lines;
    for (var i = 0; i < text.length; i += 4) {
      await Future.delayed(const Duration(milliseconds: 20));
      yield TranslateChunk(
          textDelta: text.substring(i, (i + 4).clamp(0, text.length)));
    }
    _translations['$meetingId|$target'] = text;
    yield const TranslateChunk(done: true);
  }

  @override
  Future<String?> getTranslation(String meetingId,
      {required String target}) async {
    await Future.delayed(const Duration(milliseconds: 150));
    return _translations['$meetingId|$target'];
  }

  @override
  Uri resolveUri(String pathOrUrl) => Uri.parse(pathOrUrl);

  @override
  Future<Map<String, String>> authHeaders() async => const {};

  @override
  void dispose() {}
}

class _MockTranscriptionSession implements TranscriptionSession {
  _MockTranscriptionSession({required this.config, required this.onFinal}) {
    _timer = Timer.periodic(const Duration(milliseconds: 1600), (_) => _tick());
  }

  final TranscriptionConfig config;
  final void Function(TranscriptSegment) onFinal;
  final _controller = StreamController<TranscriptUpdate>.broadcast();
  final _finals = <TranscriptSegment>[]; // 已定稿(累積)
  Timer? _timer;
  int _idx = 0;
  int _partial = 0;

  /// Mock 永遠視為連線正常、無缺口。
  @override
  Stream<TranscriptionLinkState> get linkState =>
      Stream.value(TranscriptionLinkState.online);

  @override
  bool get hadGap => false;

  @override
  DateTime? get droppedAt => null;

  @override
  void reconnectNow() {}

  static const _lines = [
    '好,我們開始今天的會議。',
    '先看一下上週待辦的進度。',
    'server 端的 API 契約我這邊已經草擬好了。',
    'Flutter 的錄音跟即時逐字稿功能正在整合。',
    '摘要用 map-reduce,長逐字稿也不會爆 context。',
    '個人助理可以問過去所有會議的內容。',
    '那這部分就先這樣,下週再追蹤。',
  ];

  void _tick() {
    if (_controller.isClosed) return;
    final line = _lines[_idx % _lines.length];
    final speaker = config.diarization
        ? '說話者 ${(_idx % (config.speakerCount ?? 2)) + 1}'
        : null;
    // 先送兩次 partial(邊錄邊出預覽),第三次把這句定稿加入累積清單。
    if (_partial < 2) {
      final take = ((_partial + 1) * line.length ~/ 3).clamp(1, line.length);
      _emit(partial: TranscriptSegment(
        id: 'tentative',
        text: line.substring(0, take),
        isFinal: false,
        speaker: speaker,
      ));
      _partial++;
    } else {
      final seg = TranscriptSegment(
        id: 'seg${_finals.length}',
        text: line,
        isFinal: true,
        speaker: speaker,
      );
      _finals.add(seg);
      onFinal(seg);
      _emit();
      _idx++;
      _partial = 0;
    }
  }

  void _emit({TranscriptSegment? partial}) {
    if (_controller.isClosed) return;
    _controller.add(TranscriptUpdate(
      finalSegments: List.of(_finals),
      partial: partial,
    ));
  }

  @override
  Stream<TranscriptUpdate> get updates => _controller.stream;

  @override
  void sendAudio(List<int> pcm16) {/* mock 忽略實際音訊 */}

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _emit(); // 收尾:送最後一份快照(無 partial)
    await _controller.close();
  }
}
