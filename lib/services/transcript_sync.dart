import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_exception.dart';
import '../providers/meetings_controller.dart';
import '../providers/service_providers.dart';
import '../providers/speaker_names_controller.dart';
import '../providers/transcript_edits_controller.dart';
import 'speaker_name_store.dart';

/// 一次同步的結果。
class TranscriptSyncResult {
  const TranscriptSyncResult.ok()
      : synced = true,
        message = null;
  const TranscriptSyncResult.failed(this.message) : synced = false;

  final bool synced;

  /// 失敗原因(已是可直接顯示給使用者的中文)。
  final String? message;
}

/// 把使用者在 App 修好的逐字稿(錯字 + 說話者)整份回存到 server。
///
/// 為什麼一定要回存:助理問答是在 server 端做 RAG,只留本機的話它查到的還是舊文字 ——
/// 使用者改正了人名,問助理卻仍得到錯的那個。server 存完會背景重建向量索引。
///
/// 本機修訂的角色因此變成**待同步緩衝**:先寫本機(離線也不會丟),再推 server;
/// 推成功就清掉本機那份,之後以 server 為單一真相來源。
class TranscriptSync {
  TranscriptSync._();

  /// 推送目前顯示的逐字稿。呼叫端負責顯示 [TranscriptSyncResult.message]。
  static Future<TranscriptSyncResult> push(Ref ref, String meetingId) async {
    // 目前顯示的 = server 原文 + 本機修訂,正是要成為新原文的內容。
    final current = ref.read(transcriptProvider(meetingId)).valueOrNull;
    if (current == null || current.isEmpty) {
      return const TranscriptSyncResult.failed('逐字稿還沒載入,稍後再試。');
    }
    // server 對空白段落回 400。與其讓它擋下來,先在這裡說清楚哪裡有問題。
    if (current.any((s) => s.text.trim().isEmpty)) {
      return const TranscriptSyncResult.failed('有段落是空白的,請補上文字或改回原文再同步。');
    }

    try {
      await ref.read(backendProvider).putTranscript(meetingId, current);
    } on ApiException catch (e) {
      // 409(錄音/轉錄中)、400、離線都走這裡。本機修訂保留,之後可重試。
      return TranscriptSyncResult.failed(e.message);
    } catch (e) {
      return TranscriptSyncResult.failed('同步失敗:$e');
    }

    // 成功:server 的內容現在就等於我們剛送出去的那份。先讓 raw 採用它,
    // 再清掉本機修訂 —— 順序反過來會有一瞬間顯示未修訂的舊文字。
    ref.read(rawTranscriptProvider(meetingId).notifier).adopt(current);
    await ref.read(transcriptEditStoreProvider).clearAll(meetingId);
    ref.invalidate(transcriptEditsProvider(meetingId));
    await ref
        .read(speakerNameStoreProvider)
        .save(meetingId, const SpeakerPrefs());
    ref.invalidate(speakerPrefsProvider(meetingId));
    return const TranscriptSyncResult.ok();
  }
}
