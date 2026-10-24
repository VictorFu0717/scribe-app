import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/meeting.dart';
import '../models/transcript_segment.dart';
import '../services/backend.dart';
import '../services/local_meeting_data.dart';
import '../services/speaker_name_store.dart';
import '../services/transcript_edit_store.dart';
import 'service_providers.dart';
import 'speaker_names_controller.dart';
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

  /// 刪除會議:先刪 server,成功後再清掉手機上的錄音檔與本機記錄。
  ///
  /// 順序不能反:server 刪失敗(離線、逾時)時要保留錄音,免得 server 上的
  /// 會議還在、錄音卻已經沒了。
  Future<void> delete(String id) async {
    await ref.read(backendProvider).deleteMeeting(id);
    await purgeLocalMeetingData(ref.read, id);
    ref.invalidateSelf();
  }
}

/// 單場會議詳情。
final meetingProvider =
    FutureProvider.family<Meeting, String>((ref, id) async {
  return ref.watch(backendProvider).getMeeting(id);
});

/// 這個使用者用過的所有標籤(給輸入時的建議清單)。
///
/// 標籤要能重複使用才有篩選價值 —— 每次自由打字很容易打出「專案會議」與
/// 「專案會譯」這種近似但不同的標籤,助理就篩不到一起。
final meetingTagsProvider = FutureProvider<List<MeetingTag>>((ref) async {
  return ref.watch(backendProvider).listTags();
});

/// 逐字稿的原始內容(server 回來的,未套用本機修訂)。
///
/// 需要重新向 server 取逐字稿時 invalidate 這個(下拉重新整理、重新轉錄)。
/// 畫面請用 [transcriptProvider]。
final rawTranscriptProvider = AsyncNotifierProvider.family<
    RawTranscriptController, List<TranscriptSegment>, String>(
  RawTranscriptController.new,
);

class RawTranscriptController
    extends FamilyAsyncNotifier<List<TranscriptSegment>, String> {
  @override
  Future<List<TranscriptSegment>> build(String meetingId) {
    return ref.watch(backendProvider).getTranscript(meetingId);
  }

  /// 採用一份**已知等同 server 內容**的逐字稿(剛剛 PUT 成功的那份)。
  ///
  /// 用這個而不是 invalidate:invalidate 會重抓、期間進入 loading,畫面整份換成
  /// 轉圈圈而捲動位置歸零(先前修過的問題)。既然剛寫進去的內容就是 server 的
  /// 內容,沒有理由再抓一次。
  void adopt(List<TranscriptSegment> segments) {
    state = AsyncData(List.unmodifiable(segments));
  }
}

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
  final speakers = ref.watch(speakerPrefsProvider(id));
  return raw.whenData((segments) => applySpeakerPrefs(
        applyTranscriptEdits(segments, edits),
        speakers,
      ));
});
