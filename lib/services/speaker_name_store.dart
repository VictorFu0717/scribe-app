import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/transcript_segment.dart';
import 'transcript_edit_store.dart';

/// 把某一段指派給另一位說話者。
///
/// [speaker] 存的是**原始標籤**(如 `說話者 2`)或自建說話者的鍵,不是顯示名稱 ——
/// 這樣日後把該人改名,這段也會跟著變,不會留著舊名字。
///
/// [original] 是 server 原本判定的說話者,用來偵測這條指派是否已過期(重新轉錄後
/// 同一個時間點可能換人了),與文字修訂的做法一致。
class SpeakerAssignment {
  const SpeakerAssignment({required this.speaker, required this.original});

  final String speaker;
  final String original;

  Map<String, dynamic> toJson() => {'speaker': speaker, 'original': original};

  static SpeakerAssignment? fromJson(Object? json) {
    if (json is! Map) return null;
    final speaker = json['speaker'];
    final original = json['original'];
    if (speaker is! String || original is! String) return null;
    return SpeakerAssignment(speaker: speaker, original: original);
  }
}

/// 一場會議的說話者設定:改名 + 個別段落的指派。
class SpeakerPrefs {
  const SpeakerPrefs({this.names = const {}, this.assignments = const {}});

  /// 原始標籤(或自建說話者的鍵)→ 顯示名稱。例:`{'說話者 1': '小明'}`。
  final Map<String, String> names;

  /// 段落 key → 指派。用於「這句其實是別人說的」。
  final Map<String, SpeakerAssignment> assignments;

  bool get isEmpty => names.isEmpty && assignments.isEmpty;

  /// 某個標籤目前顯示成什麼。沒改名就是原樣。
  String displayName(String canonical) => names[canonical] ?? canonical;

  SpeakerPrefs copyWith({
    Map<String, String>? names,
    Map<String, SpeakerAssignment>? assignments,
  }) =>
      SpeakerPrefs(
        names: names ?? this.names,
        assignments: assignments ?? this.assignments,
      );
}

/// 說話者改名與逐段指派(存在手機本機)。
///
/// server 沒有修改說話者的端點,所以與文字修訂一樣存本機、在讀取逐字稿時疊上。
class SpeakerNameStore {
  SpeakerNameStore(this._prefs);

  final SharedPreferences _prefs;

  /// 自建說話者的鍵前綴 —— diarization 可能把兩個人併成一個,使用者需要能新增
  /// 一位原本不存在的說話者。用固定前綴才不會和 server 的標籤撞名。
  static const customPrefix = 'custom:';

  static String customKey(int n) => '$customPrefix$n';

  String _key(String meetingId) => 'speaker_prefs.$meetingId';

  SpeakerPrefs prefsFor(String meetingId) {
    final raw = _prefs.getString(_key(meetingId));
    if (raw == null) return const SpeakerPrefs();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const SpeakerPrefs();
      final names = <String, String>{};
      final rawNames = decoded['names'];
      if (rawNames is Map) {
        rawNames.forEach((k, v) {
          if (k is String && v is String && v.isNotEmpty) names[k] = v;
        });
      }
      final assignments = <String, SpeakerAssignment>{};
      final rawAssign = decoded['assignments'];
      if (rawAssign is Map) {
        rawAssign.forEach((k, v) {
          final a = SpeakerAssignment.fromJson(v);
          if (k is String && a != null) assignments[k] = a;
        });
      }
      return SpeakerPrefs(names: names, assignments: assignments);
    } catch (_) {
      return const SpeakerPrefs(); // 壞資料不該讓逐字稿讀不出來
    }
  }

  Future<void> save(String meetingId, SpeakerPrefs prefs) {
    if (prefs.isEmpty) return _prefs.remove(_key(meetingId));
    return _prefs.setString(
      _key(meetingId),
      jsonEncode({
        'names': prefs.names,
        'assignments':
            prefs.assignments.map((k, v) => MapEntry(k, v.toJson())),
      }),
    );
  }
}

/// 把說話者設定疊到逐字稿上。
///
/// 順序:先看這段有沒有被指派給別人,再套改名 —— 反過來會讓指派拿到顯示名稱
/// 當標籤,之後改名就對不上了。
List<TranscriptSegment> applySpeakerPrefs(
  List<TranscriptSegment> segments,
  SpeakerPrefs prefs,
) {
  if (prefs.isEmpty) return segments;
  var changed = false;
  final out = <TranscriptSegment>[];
  for (var i = 0; i < segments.length; i++) {
    final seg = segments[i];
    final canonical = canonicalSpeaker(seg, i, prefs);
    if (canonical == null) {
      out.add(seg);
      continue;
    }
    final display = prefs.displayName(canonical);
    if (display != seg.speaker) {
      out.add(seg.copyWith(speaker: display));
      changed = true;
    } else {
      out.add(seg);
    }
  }
  return changed ? out : segments;
}

/// 這一段目前歸屬的**原始標籤**(套用指派後、未套改名)。
///
/// 傳入的必須是 server 原始的片段(未疊過設定的),否則 [SpeakerAssignment.original]
/// 的比對會失準。沒有說話者資訊時回 null。
String? canonicalSpeaker(
  TranscriptSegment segment,
  int index,
  SpeakerPrefs prefs,
) {
  final assigned = prefs.assignments[TranscriptEditStore.keyFor(segment, index)];
  if (assigned != null && assigned.original == (segment.speaker ?? '')) {
    return assigned.speaker;
  }
  return segment.speaker;
}
