import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/transcript_segment.dart';
import '../services/speaker_name_store.dart';
import '../services/transcript_edit_store.dart';
import 'service_providers.dart';

/// 單一會議的說話者設定(改名 + 逐段指派),以 meetingId 為 key。
final speakerPrefsProvider =
    NotifierProvider.family<SpeakerPrefsController, SpeakerPrefs, String>(
  SpeakerPrefsController.new,
);

class SpeakerPrefsController extends FamilyNotifier<SpeakerPrefs, String> {
  @override
  SpeakerPrefs build(String meetingId) =>
      ref.read(speakerNameStoreProvider).prefsFor(meetingId);

  Future<void> _persist(SpeakerPrefs prefs) async {
    state = prefs;
    await ref.read(speakerNameStoreProvider).save(arg, prefs);
  }

  /// 把某位說話者改名 —— 套用到這場會議的**所有**段落。
  ///
  /// [canonical] 必須是原始標籤或自建說話者的鍵,不能是顯示名稱。
  Future<void> rename(String canonical, String name) {
    final names = Map<String, String>.of(state.names);
    final trimmed = name.trim();
    // 改回原本的標籤等於沒改名,不留無意義的記錄。
    if (trimmed.isEmpty || trimmed == canonical) {
      names.remove(canonical);
    } else {
      names[canonical] = trimmed;
    }
    return _persist(state.copyWith(names: names));
  }

  /// 把某一段指派給另一位說話者(這句其實是別人說的)。
  ///
  /// [rawSegment] 必須是 server 原始的片段,否則 original 比對會失準。
  Future<void> assign(
    TranscriptSegment rawSegment,
    int index,
    String canonical,
  ) {
    final key = TranscriptEditStore.keyFor(rawSegment, index);
    final assignments = Map<String, SpeakerAssignment>.of(state.assignments);
    final original = rawSegment.speaker ?? '';
    if (canonical == original) {
      assignments.remove(key); // 指回原本的人 = 取消指派
    } else {
      assignments[key] =
          SpeakerAssignment(speaker: canonical, original: original);
    }
    return _persist(state.copyWith(assignments: assignments));
  }

  /// 新增一位原本不存在的說話者(diarization 把兩人併成一個時需要),回傳其鍵。
  Future<String> addSpeaker(String name) async {
    // 找一個沒被用過的編號,避免刪掉再新增時撞到舊鍵。
    var n = 1;
    while (state.names.containsKey(SpeakerNameStore.customKey(n))) {
      n++;
    }
    final key = SpeakerNameStore.customKey(n);
    final names = Map<String, String>.of(state.names)
      ..[key] = name.trim().isEmpty ? '說話者 $key' : name.trim();
    await _persist(state.copyWith(names: names));
    return key;
  }
}
