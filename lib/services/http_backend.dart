import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/io.dart';

import '../core/network/api_exception.dart';
import '../core/network/sse.dart';
import '../core/storage/token_storage.dart';
import '../models/auth_token.dart';
import '../models/chat_message.dart';
import '../models/meeting.dart';
import '../models/summary.dart';
import '../models/transcript_segment.dart';
import '../models/transcription_config.dart';
import 'backend.dart';

/// 對接 scribe server 的後端實作。
///
/// App 只連 scribe 這**單一對外入口**;所有 AI/ML(ASR、LLM、RAG)都由 server
/// 內部轉發到 vLLM/Ollama,client 不直連任何模型服務。
class HttpBackend implements Backend {
  HttpBackend({
    required String baseUrl,
    required TokenStorage tokenStorage,
    http.Client? client,
  })  : _base = _normalize(baseUrl),
        _tokenStorage = tokenStorage,
        _client = client ?? http.Client();

  final Uri _base;
  final TokenStorage _tokenStorage;
  final http.Client _client;

  static Uri _normalize(String baseUrl) {
    var b = baseUrl.trim();
    if (b.endsWith('/')) b = b.substring(0, b.length - 1);
    return Uri.parse(b);
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final p = path.startsWith('/') ? path : '/$path';
    return _base.replace(
      path: '${_base.path}$p',
      queryParameters: query?.isEmpty ?? true ? null : query,
    );
  }

  /// 讀 token;keychain 暫時不可用時回 null 而非丟例外,不讓認證讀取拖垮請求。
  Future<AuthToken?> _safeToken() async {
    try {
      return await _tokenStorage.read();
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, String>> _headers({bool json = true}) async {
    final token = await _safeToken();
    return {
      if (json) 'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': token.authorizationHeader,
    };
  }

  Never _throw(http.Response r) =>
      throw ApiException.fromResponse(r.statusCode, r.body);

  dynamic _decode(http.Response r) {
    if (r.statusCode < 200 || r.statusCode >= 300) _throw(r);
    if (r.body.isEmpty) return null;
    return jsonDecode(utf8.decode(r.bodyBytes));
  }

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException.network(e);
    }
  }

  // ── Auth ──
  @override
  Future<AuthToken> login({
    required String username,
    required String password,
  }) {
    return _guard(() async {
      // 相容 FastAPI OAuth2PasswordRequestForm(form-urlencoded)。
      final r = await _client.post(
        _uri('/auth/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': 'password',
          'username': username,
          'password': password,
        },
      );
      final data = _decode(r) as Map<String, dynamic>;
      final token = AuthToken.fromJson(data);
      await _tokenStorage.write(token);
      return token;
    });
  }

  @override
  Future<AuthToken> register({
    required String username,
    required String password,
  }) {
    return _guard(() async {
      // POST /auth/register — JSON body → 回 token(註冊即登入)。
      final r = await _client.post(
        _uri('/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
      );
      final data = _decode(r) as Map<String, dynamic>;
      final token = AuthToken.fromJson(data);
      await _tokenStorage.write(token);
      return token;
    });
  }

  // ── Meetings ──
  @override
  Future<List<Meeting>> listMeetings() {
    return _guard(() async {
      final r = await _client.get(_uri('/meetings'), headers: await _headers());
      final data = _decode(r);
      final list = data is Map ? (data['items'] ?? data['meetings']) : data;
      return (list as List)
          .map((e) => Meeting.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  @override
  Future<Meeting> getMeeting(String id) {
    return _guard(() async {
      final r =
          await _client.get(_uri('/meetings/$id'), headers: await _headers());
      return Meeting.fromJson(_decode(r) as Map<String, dynamic>);
    });
  }

  @override
  Future<Meeting> createMeeting({required String title}) {
    return _guard(() async {
      final r = await _client.post(
        _uri('/meetings'),
        headers: await _headers(),
        body: jsonEncode({'title': title}),
      );
      return Meeting.fromJson(_decode(r) as Map<String, dynamic>);
    });
  }

  @override
  Future<void> deleteMeeting(String id) {
    return _guard(() async {
      final r = await _client.delete(_uri('/meetings/$id'),
          headers: await _headers());
      if (r.statusCode < 200 || r.statusCode >= 300) _throw(r);
    });
  }

  @override
  Future<List<TranscriptSegment>> getTranscript(String meetingId) {
    return _guard(() async {
      final r = await _client.get(_uri('/meetings/$meetingId/transcript'),
          headers: await _headers());
      final data = _decode(r);
      final list = data is Map ? (data['segments'] ?? data['items']) : data;
      if (list is! List) return <TranscriptSegment>[];
      return list
          .map((e) => TranscriptSegment.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  @override
  Future<MeetingSummary?> getSummary(String meetingId) {
    return _guard(() async {
      final r = await _client.get(_uri('/meetings/$meetingId/summary'),
          headers: await _headers());
      if (r.statusCode == 404) return null;
      final data = _decode(r);
      if (data == null) return null;
      return MeetingSummary.fromJson(data as Map<String, dynamic>);
    });
  }

  // ── 轉錄 ──
  @override
  TranscriptionSession openTranscription({
    required String meetingId,
    required TranscriptionConfig config,
  }) {
    return _HttpTranscriptionSession(
      base: _base,
      meetingId: meetingId,
      config: config,
      tokenStorage: _tokenStorage,
    );
  }

  @override
  Future<Meeting> uploadAudio(
    String meetingId,
    String filePath, {
    required TranscriptionConfig config,
  }) {
    return _guard(() async {
      final req = http.MultipartRequest(
        'POST',
        _uri('/meetings/$meetingId/audio'),
      );
      final token = await _safeToken();
      if (token != null) {
        req.headers['Authorization'] = token.authorizationHeader;
      }
      // server 以 Form 欄位讀取 diarization(非 query)。
      req.fields['diarization'] = config.diarization.toString();
      req.files.add(await http.MultipartFile.fromPath('file', filePath));
      final streamed = await _client.send(req);
      final r = await http.Response.fromStream(streamed);
      return Meeting.fromJson(_decode(r) as Map<String, dynamic>);
    });
  }

  // ── 摘要(SSE) ──
  @override
  Stream<SummaryChunk> summarize(String meetingId) async* {
    final events = await _openSse(
      'POST',
      _uri('/meetings/$meetingId/summarize'),
      body: jsonEncode({'language': 'zh-Hant'}),
    );
    await for (final e in events) {
      if (e.data == '[DONE]' || e.event == 'done') {
        MeetingSummary? summary;
        if (e.data.isNotEmpty && e.data != '[DONE]') {
          summary = _tryParseSummary(e.data);
        }
        yield SummaryChunk(summary: summary, done: true);
        return;
      }
      final chunk = _parseSummaryEvent(e);
      if (chunk != null) yield chunk;
    }
    yield const SummaryChunk(done: true);
  }

  SummaryChunk? _parseSummaryEvent(SseEvent e) {
    // 支援兩種 server 格式:純文字 delta,或 JSON。
    final data = e.data;
    if (data.isEmpty) return null;
    if (e.event == 'summary' || data.trimLeft().startsWith('{')) {
      try {
        final j = jsonDecode(data);
        if (j is Map<String, dynamic>) {
          if (j.containsKey('delta') || j.containsKey('text')) {
            return SummaryChunk(
                textDelta: (j['delta'] ?? j['text']).toString());
          }
          return SummaryChunk(summary: MeetingSummary.fromJson(j));
        }
      } catch (_) {
        // 當作純文字
      }
    }
    return SummaryChunk(textDelta: data);
  }

  MeetingSummary? _tryParseSummary(String data) {
    try {
      final j = jsonDecode(data);
      if (j is Map<String, dynamic>) return MeetingSummary.fromJson(j);
    } catch (_) {}
    return null;
  }

  // ── 助理聊天(SSE) ──
  @override
  Stream<ChatChunk> chat({
    required List<ChatMessage> messages,
    String? meetingScopeId,
  }) async* {
    // server /assistant/chat 是 agentic loop:單場(帶 meeting_id)與跨會議(RAG)都由它處理。
    final events = await _openSse(
      'POST',
      _uri('/assistant/chat'),
      body: jsonEncode({
        'messages': messages.map((m) => m.toWireJson()).toList(),
        if (meetingScopeId != null) 'meeting_id': meetingScopeId,
        'language': 'zh-Hant',
      }),
    );
    await for (final e in events) {
      if (e.data == '[DONE]' || e.event == 'done') {
        yield const ChatChunk(done: true);
        return;
      }
      final delta = _parseChatDelta(e.data);
      if (delta != null && delta.isNotEmpty) yield ChatChunk(textDelta: delta);
    }
    yield const ChatChunk(done: true);
  }

  String? _parseChatDelta(String data) {
    if (data.isEmpty) return null;
    if (data.trimLeft().startsWith('{')) {
      try {
        final j = jsonDecode(data);
        if (j is Map<String, dynamic>) {
          // 支援 OpenAI 相容格式與自訂格式。
          if (j['choices'] is List && (j['choices'] as List).isNotEmpty) {
            final delta = (j['choices'][0]['delta'] ?? j['choices'][0]['message']);
            if (delta is Map) return delta['content']?.toString();
          }
          return (j['delta'] ?? j['text'] ?? j['content'])?.toString();
        }
      } catch (_) {
        return data;
      }
    }
    return data;
  }

  // ── 翻譯 ──
  @override
  Stream<TranslateChunk> translate(String meetingId,
      {required String target}) async* {
    final events = await _openSse(
      'POST',
      _uri('/meetings/$meetingId/translate'),
      body: jsonEncode({'target': target}),
    );
    await for (final e in events) {
      if (e.data == '[DONE]' || e.event == 'done') {
        yield const TranslateChunk(done: true);
        return;
      }
      if (e.data.isEmpty) continue;
      // server 送 {"delta":"..."};出錯時送 {"error":"..."}。
      if (e.data.trimLeft().startsWith('{')) {
        try {
          final j = jsonDecode(e.data);
          if (j is Map<String, dynamic>) {
            final err = j['error']?.toString();
            if (err != null && err.isNotEmpty) {
              yield TranslateChunk(error: err, done: true);
              return;
            }
            final delta = (j['delta'] ?? j['text'])?.toString();
            if (delta != null && delta.isNotEmpty) {
              yield TranslateChunk(textDelta: delta);
            }
            continue;
          }
        } catch (_) {
          // 非 JSON 就當純文字 delta。
        }
      }
      yield TranslateChunk(textDelta: e.data);
    }
    yield const TranslateChunk(done: true);
  }

  @override
  Future<String?> getTranslation(String meetingId,
      {required String target}) {
    return _guard(() async {
      final r = await _client.get(
        _uri('/meetings/$meetingId/translation', {'target': target}),
        headers: await _headers(),
      );
      if (r.statusCode == 404) return null; // 尚未翻譯過
      final data = _decode(r);
      if (data is Map<String, dynamic>) return data['text']?.toString();
      return null;
    });
  }

  /// 開一個 SSE 連線(POST body)。回傳事件流;非 2xx 直接丟 ApiException。
  Future<Stream<SseEvent>> _openSse(String method, Uri uri,
      {String? body}) async {
    try {
      final req = http.Request(method, uri);
      req.headers.addAll(await _headers());
      req.headers['Accept'] = 'text/event-stream';
      if (body != null) req.body = body;
      final resp = await _client.send(req);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        final text = await resp.stream.bytesToString();
        throw ApiException.fromResponse(resp.statusCode, text);
      }
      return parseSse(resp.stream);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException.network(e);
    }
  }

  // ── 播放輔助 ──
  @override
  Uri resolveUri(String pathOrUrl) {
    if (pathOrUrl.startsWith('http://') || pathOrUrl.startsWith('https://')) {
      return Uri.parse(pathOrUrl);
    }
    return _uri(pathOrUrl);
  }

  @override
  Future<Map<String, String>> authHeaders() async {
    final token = await _safeToken();
    return {if (token != null) 'Authorization': token.authorizationHeader};
  }

  @override
  void dispose() => _client.close();
}

/// WebSocket 即時轉錄連線 —— 對接 scribe `WS /ws/asr`。
///
/// 協定(與 server main.py 一致):
///   Client → Server:
///     - 首先送控制訊息 `{"type":"config","diarization":bool,"speaker_count"?:int,"meeting_id":id}`
///     - binary:PCM16 LE mono 16k
///     - 結束送 `{"type":"end"}`,server 完成所有定稿後回 `final`
///   Server → Client(累積式 JSON):
///     - `{"type":"partial","tentative":..,"segments":[{"speaker","text"}],...}`
///     - `{"type":"final","text":..,"segments":[...]}`
///     - `{"type":"config",...}` / `{"type":"error","detail":..}`
/// 第 [attempt] 次重連前要等幾秒。
///
/// **錄音期間永不放棄重連**,所以這裡對任何 attempt 都回傳有限秒數。
/// 先前有 12 次上限,累計約 81 秒就轉為 failed 且再也不嘗試 —— 但錄音可能持續
/// 數小時,VPN/行動網路中斷往往好幾分鐘後才恢復;放棄之後使用者無從補救,
/// 只能停止錄音重開。重試成本只是一個 Timer,不值得設上限。
///
/// 前幾次快速重試(對付 VPN 這類短暫抖動),之後穩定在 15 秒一次。
int wsRetryDelaySeconds(int attempt) => switch (attempt) {
      <= 1 => 1,
      2 => 2,
      3 => 3,
      4 || 5 || 6 => 5,
      _ => 15,
    };

class _HttpTranscriptionSession implements TranscriptionSession {
  _HttpTranscriptionSession({
    required Uri base,
    required this.meetingId,
    required this.config,
    required TokenStorage tokenStorage,
  })  : _base = base,
        _tokenStorage = tokenStorage {
    _connect();
  }

  final Uri _base;
  final String meetingId;
  final TranscriptionConfig config;
  final TokenStorage _tokenStorage;

  IOWebSocketChannel? _channel;
  final _controller = StreamController<TranscriptUpdate>.broadcast();
  final _linkState = StreamController<TranscriptionLinkState>.broadcast();
  final _pendingAudio = <List<int>>[];
  final _finalReceived = Completer<void>();
  bool _ready = false;
  bool _closed = false;

  /// 重連相關。網路不穩(VPN、行動網路切換)時 WS 會斷,先前沒有重連機制,
  /// 一斷就再也送不出音訊 —— 使用者可能錄很久才發現逐字稿早已停止。
  int _attempt = 0;
  Timer? _retryTimer;
  bool _gap = false;

  /// 這次斷線是何時開始的(供 UI 顯示已中斷多久)。連上後清空。
  DateTime? _droppedAt;
  DateTime? get droppedAt => _droppedAt;

  /// 重連期間最多緩衝這麼多音訊(2 分鐘 @16kHz/16-bit mono = 32KB/s ≈ 3.75MB)。
  ///
  /// 抓 2 分鐘是因為 VPN/行動網路重連通常在這個區間內完成 —— 撐得過去就完全沒有
  /// 缺口。先前只緩衝 30 秒,稍長一點的抖動就開始丟音訊。
  ///
  /// 但不無限緩衝:斷線可能持續整場會議,記憶體撐不住。超過就丟棄並標記 hadGap,
  /// 由「整檔重新轉錄」補回 —— 本機錄音檔一直是完整的。
  static const _maxPendingBytes = 2 * 60 * 32 * 1024;
  int _pendingBytes = 0;

  @override
  Stream<TranscriptUpdate> get updates => _controller.stream;

  @override
  Stream<TranscriptionLinkState> get linkState => _linkState.stream;

  @override
  bool get hadGap => _gap;

  void _setLink(TranscriptionLinkState s) {
    if (!_linkState.isClosed) _linkState.add(s);
  }

  Future<void> _connect() async {
    try {
      // 讀 token 失敗(例如 keychain 暫時不可用)不應中斷轉錄,無 header 續連。
      AuthToken? token;
      try {
        token = await _tokenStorage.read();
      } catch (_) {}
      final wsScheme = _base.scheme == 'https' ? 'wss' : 'ws';
      final uri = _base.replace(
        scheme: wsScheme,
        path: '${_base.path}/ws/asr',
      );
      final channel = IOWebSocketChannel.connect(
        uri,
        headers: {
          if (token != null) 'Authorization': token.authorizationHeader,
        },
      );
      _channel = channel;

      channel.stream.listen(
        _onMessage,
        // 斷線不再直接放棄:自動重連。server 支援以同一 meeting_id 續錄,
        // 重連後新的音訊會接續寫入同一場逐字稿。
        onError: (_) => _handleDrop(),
        onDone: _handleDrop,
        cancelOnError: false,
      );

      // 先送 config(diarization、指定人數、關聯 meeting_id、JWT)。
      // token 也放進 config(server 支援 header / ?token= / config 三種帶法),
      // 確保 AUTH_REQUIRED 時 WS 也能認到身分。
      channel.sink.add(jsonEncode({
        'type': 'config',
        'diarization': config.diarization,
        if (config.speakerCount != null) 'speaker_count': config.speakerCount,
        'meeting_id': meetingId,
        if (token != null) 'token': token.accessToken,
      }));

      _ready = true;
      _attempt = 0;
      _droppedAt = null;
      _setLink(TranscriptionLinkState.online);
      for (final chunk in _pendingAudio) {
        channel.sink.add(chunk);
      }
      _pendingAudio.clear();
      _pendingBytes = 0;
    } catch (e) {
      _handleDrop();
    }
  }

  /// 連線掉了(錯誤或被關閉):排程重連。使用者主動 stop 時不重連。
  void _handleDrop() {
    if (_closed) return;
    _ready = false;
    _droppedAt ??= DateTime.now();
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;

    _attempt++;
    _setLink(TranscriptionLinkState.reconnecting);

    final secs = wsRetryDelaySeconds(_attempt);
    _retryTimer?.cancel();
    _retryTimer = Timer(Duration(seconds: secs), () {
      if (!_closed) _connect();
    });
  }

  /// 立刻重試連線(使用者按「重新連線」時用,不必等退避計時)。
  void reconnectNow() {
    if (_closed) return;
    _retryTimer?.cancel();
    _attempt = 0; // 重設退避,手動觸發視為新的一輪
    _connect();
  }

  void _onMessage(dynamic message) {
    if (message is! String) return; // 音訊是單向上傳;下行只有 JSON 文字
    Map<String, dynamic> j;
    try {
      final decoded = jsonDecode(message);
      if (decoded is! Map<String, dynamic>) return;
      j = decoded;
    } catch (_) {
      return;
    }

    switch (j['type']) {
      case 'partial':
        _controller.add(_toUpdate(j, isFinal: false));
        break;
      case 'final':
        _controller.add(_toUpdate(j, isFinal: true));
        if (!_finalReceived.isCompleted) _finalReceived.complete();
        break;
      case 'error':
        if (!_controller.isClosed) {
          _controller
              .addError(ApiException((j['detail'] ?? '轉錄錯誤').toString()));
        }
        break;
      default:
        break; // config 等控制回覆:忽略
    }
  }

  /// 把 server 的累積式訊息轉成一份 [TranscriptUpdate] 快照。
  TranscriptUpdate _toUpdate(Map<String, dynamic> j, {required bool isFinal}) {
    final rawSegs = j['segments'];
    final finals = <TranscriptSegment>[];
    if (rawSegs is List) {
      for (var i = 0; i < rawSegs.length; i++) {
        final s = rawSegs[i];
        if (s is! Map) continue;
        final text = (s['text'] ?? '').toString();
        if (text.isEmpty) continue;
        final spk = s['speaker'];
        finals.add(TranscriptSegment(
          id: 'seg$i',
          text: text,
          isFinal: true,
          speaker: (spk is String && spk.isNotEmpty) ? spk : null,
          // 時間戳:供事後對照錄音(逐字稿可點時間跳到該處播放)。
          startMs: (s['start_ms'] as num?)?.toInt(),
          endMs: (s['end_ms'] as num?)?.toInt(),
        ));
      }
    }

    // final 訊息不再有預覽;partial 才帶當前預覽(tentative)。
    TranscriptSegment? partial;
    if (!isFinal) {
      final tentative = (j['tentative'] ?? '').toString();
      if (tentative.isNotEmpty) {
        partial = TranscriptSegment(
          id: 'tentative',
          text: tentative,
          isFinal: false,
        );
      }
    }
    return TranscriptUpdate(finalSegments: finals, partial: partial);
  }

  @override
  void sendAudio(List<int> pcm16) {
    if (_closed) return;
    if (_ready && _channel != null) {
      try {
        _channel!.sink.add(pcm16);
      } catch (_) {
        _handleDrop();
      }
      return;
    }
    // 斷線中:緩衝一小段等重連後補送;超過上限就丟棄並標記缺口。
    if (_pendingBytes + pcm16.length <= _maxPendingBytes) {
      _pendingAudio.add(pcm16);
      _pendingBytes += pcm16.length;
    } else {
      _gap = true;
    }
  }

  @override
  Future<void> stop() async {
    if (_closed) return;
    _closed = true;
    _retryTimer?.cancel();
    try {
      _channel?.sink.add(jsonEncode({'type': 'end'}));
      // 等 server 回 final(所有句子定稿完成);逾時則不再等,直接關閉。
      await _finalReceived.future
          .timeout(const Duration(seconds: 15), onTimeout: () {});
      await _channel?.sink.close();
    } catch (_) {}
    if (!_linkState.isClosed) await _linkState.close();
  }
}
