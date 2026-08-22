import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/meeting.dart';
import '../models/transcript_segment.dart';
import '../services/transcript_edit_store.dart';
import 'service_providers.dart';
import 'transcript_edits_controller.dart';

/// 會議清單。對應 `GET /meetings`。
final meetingsListProvider =
    AsyncNotifierProvider<MeetingsListController, List<Meeting>>(
        MeetingsListController.new);

class MeetingsListController extends AsyncNotifier<List<Meeting>> {
  @override
  Future<List<Meeting>> build() {
    return ref.watch(backendProvider).listMeetings();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
        () => ref.read(backendProvider).listMeetings());
  }

  Future<Meeting> create(String title) async {
    final meeting = await ref.read(backendProvider).createMeeting(title: title);
    ref.invalidateSelf();
    return meeting;
  }

  Future<void> delete(String id) async {
    await ref.read(backendProvider).deleteMeeting(id);
    ref.invalidateSelf();
  }
}

/// 單場會議詳情。
final meetingProvider =
    FutureProvider.family<Meeting, String>((ref, id) async {
  return ref.watch(backendProvider).getMeeting(id);
});

/// 逐字稿的原始內容(server 回來的,未套用本機修訂)。
///
/// 需要重新向 server 取逐字稿時 invalidate 這個(下拉重新整理、重新轉錄)。
/// 畫面請用 [transcriptProvider]。
final rawTranscriptProvider =
    FutureProvider.family<List<TranscriptSegment>, String>((ref, id) async {
  return ref.watch(backendProvider).getTranscript(id);
});

/// 逐字稿(已完成的會議),已疊上本機的人工修訂。
///
/// 修訂在這裡套用而非各畫面各自處理 —— 這是逐字稿的**單一讀取入口**,
/// 畫面、匯出、裝置內翻譯都經過它,才不會出現「畫面改了但匯出沒改」。
///
/// 刻意做成同步的衍生 Provider,而不是在 FutureProvider 裡 watch 修訂:
/// 後者一改字就會讓整個 future 重跑 —— 連 server 都重新抓一次,期間 AsyncValue
/// 進入 loading,畫面整份被換成轉圈圈,ListView 重建後捲回最上面。實測就是
/// 「改完一段後跳到第一行」。這樣拆開,改字只會重算這一層,底層的資料仍在,
/// 畫面不閃、捲動位置也留著。
final transcriptProvider =
    Provider.family<AsyncValue<List<TranscriptSegment>>, String>((ref, id) {
  final raw = ref.watch(rawTranscriptProvider(id));
  final edits = ref.watch(transcriptEditsProvider(id));
  return raw.whenData((segments) => applyTranscriptEdits(segments, edits));
});
