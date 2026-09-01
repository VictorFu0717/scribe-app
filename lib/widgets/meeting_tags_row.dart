import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_exception.dart';
import '../models/meeting.dart';
import '../providers/meetings_controller.dart';
import '../providers/service_providers.dart';
import '../services/backend.dart';

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

  Future<void> _add() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _TagPickerSheet(existing: widget.meeting.tags),
    );
    final tag = picked?.trim();
    if (tag == null || tag.isEmpty) return;
    // 已經有了就不必再打一次 server。
    if (widget.meeting.tags
        .any((t) => t.toLowerCase() == tag.toLowerCase())) {
      return;
    }
    await _save([...widget.meeting.tags, tag]);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tags = widget.meeting.tags;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Icon(Icons.sell_outlined, size: 14, color: scheme.outline),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final tag in tags)
                  _Chip(
                    label: tag,
                    onRemove: _busy
                        ? null
                        : () => _save(
                            tags.where((t) => t != tag).toList()),
                  ),
                _AddChip(
                  // 沒有標籤時把用途說清楚,否則沒人知道這顆按鈕在做什麼。
                  label: tags.isEmpty ? '加標籤(讓助理更準)' : '標籤',
                  onTap: _busy ? null : _add,
                ),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(left: 2),
                    child: SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, this.onRemove});
  final String label;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.only(left: 9, right: 3, top: 2, bottom: 2),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: scheme.onPrimaryContainer)),
          InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: Icon(Icons.close_rounded,
                  size: 13, color: scheme.onPrimaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddChip extends StatelessWidget {
  const _AddChip({required this.label, this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded, size: 13, color: scheme.primary),
            const SizedBox(width: 3),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: scheme.primary)),
          ],
        ),
      ),
    );
  }
}

/// 選/輸入一個標籤。優先讓使用者從既有標籤挑,挑不到才自己打。
class _TagPickerSheet extends ConsumerStatefulWidget {
  const _TagPickerSheet({required this.existing});

  /// 這場會議已有的標籤(清單中標示出來,避免重複加)。
  final List<String> existing;

  @override
  ConsumerState<_TagPickerSheet> createState() => _TagPickerSheetState();
}

class _TagPickerSheetState extends ConsumerState<_TagPickerSheet> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final all = ref.watch(meetingTagsProvider);
    final query = _ctrl.text.trim().toLowerCase();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 0),
              child: Row(
                children: [
                  const Text('加標籤',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text('助理問答時會先用標籤挑出候選會議,再從中找答案。',
                  style: TextStyle(fontSize: 12.5, color: scheme.outline)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                maxLength: 40, // 與 server 的上限一致,不讓使用者打了才被截斷
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() {}),
                onSubmitted: (v) =>
                    v.trim().isEmpty ? null : Navigator.pop(context, v),
                decoration: const InputDecoration(
                  hintText: '例如:專案會議',
                  isDense: true,
                  counterText: '',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: all.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                      child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))),
                ),
                // 取不到既有標籤不該擋住輸入 —— 自己打一個照樣能用。
                error: (_, __) => Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text('讀不到既有標籤,可直接輸入新的。',
                      style:
                          TextStyle(fontSize: 12.5, color: scheme.outline)),
                ),
                data: (tags) {
                  final matches = tags
                      .where((t) => t.tag.toLowerCase().contains(query))
                      .toList();
                  if (matches.isEmpty) return const SizedBox(height: 8);
                  return ListView(
                    shrinkWrap: true,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                        child: Text('用過的標籤',
                            style: TextStyle(
                                fontSize: 12, color: scheme.outline)),
                      ),
                      for (final t in matches)
                        _suggestion(t, scheme),
                    ],
                  );
                },
              ),
            ),
            if (_ctrl.text.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, _ctrl.text),
                    child: Text('加上「${_ctrl.text.trim()}」'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _suggestion(MeetingTag t, ColorScheme scheme) {
    final already =
        widget.existing.any((e) => e.toLowerCase() == t.tag.toLowerCase());
    return ListTile(
      dense: true,
      leading: Icon(already ? Icons.check_rounded : Icons.sell_outlined,
          size: 18, color: already ? scheme.primary : scheme.outline),
      title: Text(t.tag),
      trailing: Text('${t.count} 場',
          style: TextStyle(fontSize: 12, color: scheme.outline)),
      // 已經有了就不能再點,避免使用者以為沒生效而重複操作。
      enabled: !already,
      onTap: already ? null : () => Navigator.pop(context, t.tag),
    );
  }
}
