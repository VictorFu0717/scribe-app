import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/transcript_sync.dart';
import 'speaker_names_controller.dart';
import 'transcript_edits_controller.dart';

/// 單一會議的同步狀態。
class TranscriptSyncState {
  const TranscriptSyncState({this.busy = false, this.error});

  /// 正在推送。
  final bool busy;

  /// 上次推送失敗的原因(已是可顯示的中文);成功或還沒推過為 null。
  final String? error;
}

/// 逐字稿修訂的同步控制,以 meetingId 為 key。
final transcriptSyncProvider = NotifierProvider.family<TranscriptSyncController,
    TranscriptSyncState, String>(TranscriptSyncController.new);

class TranscriptSyncController
    extends FamilyNotifier<TranscriptSyncState, String> {
  @override
  TranscriptSyncState build(String meetingId) => const TranscriptSyncState();

  /// 是否還有修訂只存在本機(尚未回存 server)。
  ///
  /// 這件事重要到要顯示在畫面上:未同步就代表助理仍會用舊文字作答 ——
  /// 使用者以為改好了,問助理卻還是錯的。
  bool get hasPending {
    final edits = ref.read(transcriptEditsProvider(arg));
    final speakers = ref.read(speakerPrefsProvider(arg));
    return edits.isNotEmpty || !speakers.isEmpty;
  }

  /// 推送本機修訂。回傳是否成功。
  Future<bool> push() async {
    if (state.busy) return false;
    state = const TranscriptSyncState(busy: true);
    final result = await TranscriptSync.push(ref, arg);
    state = TranscriptSyncState(error: result.message);
    return result.synced;
  }
}
