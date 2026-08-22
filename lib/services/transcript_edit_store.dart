import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/transcript_segment.dart';

/// 一段逐字稿的人工修訂。
///
/// 同時記下 [original] 是為了偵測「這條修訂還適不適用」:逐字稿是每次從 server
/// 重新取回的,重新轉錄後分段與內容都可能不同,若只憑 key 硬套,修訂會落到
/// **別的句子**上。原文不吻合就視為過期而不套用(但仍保留,萬一逐字稿還原回來
/// 就又生效)。
class TranscriptEdit {
  const TranscriptEdit({required this.text, required this.original});

  final String text;
  final String original;

  Map<String, dynamic> toJson() => {'text': text, 'original': original};

  static TranscriptEdit? fromJson(Object? json) {
    if (json is! Map) return null;
    final text = json['text'];
    final original = json['original'];
    if (text is! String || original is! String) return null;
    return TranscriptEdit(text: text, original: original);
  }
}

/// 逐字稿的人工修訂(存在手機本機)。
///
/// server 目前沒有修改逐字稿的端點(只有 `GET /meetings/{id}/transcript`),
/// 所以修訂存在本機,讀取逐字稿時疊上去。影響範圍:畫面、匯出、裝置內翻譯都會
/// 用修訂後的文字;但 server 端的摘要與 AI 助理(RAG 索引)仍是原始文字。
class TranscriptEditStore {
  TranscriptEditStore(this._prefs);

  final SharedPreferences _prefs;

  String _key(String meetingId) => 'transcript_edits.$meetingId';

  /// 修訂的 key。優先用開始時間 —— 它由音訊位置決定,比 server 的 id 穩定,
  /// 而且同一場會議內不重複;沒有時間戳才退回索引。
  ///
  /// (不能只用 `segment.id`:server 沒給 id 時,model 會退化成
  /// `'${start_ms}-${end_ms}'`,兩者都缺就變成所有片段共用 `'-'` —— 那會讓一次
  /// 編輯改到整份逐字稿。)
  static String keyFor(TranscriptSegment segment, int index) {
    final ms = segment.startMs;
    return ms != null ? 'ms:$ms' : 'ix:$index';
  }

  Map<String, TranscriptEdit> editsFor(String meetingId) {
    final raw = _prefs.getString(_key(meetingId));
    if (raw == null) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      final out = <String, TranscriptEdit>{};
      decoded.forEach((k, v) {
        final edit = TranscriptEdit.fromJson(v);
        if (k is String && edit != null) out[k] = edit;
      });
      return out;
    } catch (_) {
      return const {}; // 壞資料不該讓逐字稿整份讀不出來
    }
  }

  Future<void> _write(String meetingId, Map<String, TranscriptEdit> edits) {
    if (edits.isEmpty) return _prefs.remove(_key(meetingId));
    return _prefs.setString(
      _key(meetingId),
      jsonEncode(edits.map((k, v) => MapEntry(k, v.toJson()))),
    );
  }

  /// 記錄一段修訂。[text] 與 [original] 相同時等於取消修訂。
  Future<Map<String, TranscriptEdit>> save(
    String meetingId,
    String key, {
    required String text,
    required String original,
  }) async {
    final edits = Map<String, TranscriptEdit>.of(editsFor(meetingId));
    if (text == original) {
      edits.remove(key);
    } else {
      edits[key] = TranscriptEdit(text: text, original: original);
    }
    await _write(meetingId, edits);
    return edits;
  }

  Future<Map<String, TranscriptEdit>> clear(
      String meetingId, String key) async {
    final edits = Map<String, TranscriptEdit>.of(editsFor(meetingId));
    edits.remove(key);
    await _write(meetingId, edits);
    return edits;
  }

  Future<void> clearAll(String meetingId) =>
      _prefs.remove(_key(meetingId));
}

/// 把修訂疊到 server 取回的逐字稿上。
///
/// 只有原文吻合才套用 —— 見 [TranscriptEdit] 的說明。
List<TranscriptSegment> applyTranscriptEdits(
  List<TranscriptSegment> segments,
  Map<String, TranscriptEdit> edits,
) {
  if (edits.isEmpty) return segments;
  var changed = false;
  final out = <TranscriptSegment>[];
  for (var i = 0; i < segments.length; i++) {
    final seg = segments[i];
    final edit = edits[TranscriptEditStore.keyFor(seg, i)];
    if (edit != null && edit.original == seg.text) {
      out.add(seg.copyWith(text: edit.text));
      changed = true;
    } else {
      out.add(seg);
    }
  }
  return changed ? out : segments;
}
