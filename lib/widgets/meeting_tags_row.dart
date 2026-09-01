import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_exception.dart';
import '../models/meeting.dart';
import '../providers/meetings_controller.dart';
import '../providers/service_providers.dart';
import 'tag_editor_row.dart';

/// 會議標籤列(標題底下)。可新增/移除,標籤是選填的。
///
/// 標籤存在 server —— 它會在助理問答時**於向量檢索當下**就用標籤限制候選會議,
/// 所以標籤下得準,回答就準。這也是為什麼要存回 server 而不是像文字修訂那樣留在
/// 本機:留本機的話 RAG 看不到。
class MeetingTagsRow extends ConsumerStatefulWidget {
  const MeetingTagsRow({super.key, required this.meeting});

  final Meeting meeting;

  @override
  ConsumerState<MeetingTagsRow> createState() => _MeetingTagsRowState();
}

class _MeetingTagsRowState extends ConsumerState<MeetingTagsRow> {
  bool _busy = false;

  /// 整組覆寫成 [tags](server 的 PATCH 語意就是整組覆寫)。
  Future<void> _save(List<String> tags) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(backendProvider)
          .updateMeeting(widget.meeting.id, tags: tags);
      // 以 server 回來的為準(它會去重、限長),不自行猜測結果。
      ref.invalidate(meetingProvider(widget.meeting.id));
      ref.invalidate(meetingsListProvider);
      ref.invalidate(meetingTagsProvider); // 建議清單要跟著更新
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e is ApiException ? e.message : '標籤儲存失敗:$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: TagEditorRow(
        tags: widget.meeting.tags,
        onChanged: _save,
        busy: _busy,
      ),
    );
  }
}
