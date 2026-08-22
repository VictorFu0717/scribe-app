import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/transcript_segment.dart';
import '../services/transcript_edit_store.dart';
import 'service_providers.dart';

/// 單一會議的逐字稿人工修訂,以 meetingId 為 key。
///
/// 逐字稿本身每次都從 server 重新取回,修訂則存在本機;`transcriptProvider`
/// 讀取後會把修訂疊上去,所以畫面、匯出、裝置內翻譯拿到的都是修訂後的文字。
final transcriptEditsProvider = NotifierProvider.family<
    TranscriptEditsController, Map<String, TranscriptEdit>, String>(
  TranscriptEditsController.new,
);

class TranscriptEditsController
    extends FamilyNotifier<Map<String, TranscriptEdit>, String> {
  @override
  Map<String, TranscriptEdit> build(String meetingId) =>
      ref.read(transcriptEditStoreProvider).editsFor(meetingId);

  /// 修改某一段的文字。[index] 是該片段在目前逐字稿中的位置(用於組 key)。
  Future<void> edit(TranscriptSegment segment, int index, String text) async {
    final key = TranscriptEditStore.keyFor(segment, index);
    // original 一律存**server 的原文**,而非目前顯示的文字 —— 否則反覆編輯後
    // original 會變成上一次的修訂,日後就對不上 server 回來的逐字稿而失效。
    final original =
        state[key]?.original ?? segment.text;
    state = await ref.read(transcriptEditStoreProvider).save(
          arg,
          key,
          text: text.trim(),
          original: original,
        );
  }

  /// 還原成 server 的原文。
  Future<void> revert(TranscriptSegment segment, int index) async {
    final key = TranscriptEditStore.keyFor(segment, index);
    state = await ref.read(transcriptEditStoreProvider).clear(arg, key);
  }

  /// 這段目前的修訂;沒改過回 null。
  TranscriptEdit? editFor(TranscriptSegment segment, int index) =>
      state[TranscriptEditStore.keyFor(segment, index)];
}
