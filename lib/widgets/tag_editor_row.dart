import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/meetings_controller.dart';
import '../services/backend.dart';

/// 標籤編輯列(純呈現)。狀態由呼叫端持有 —— 錄音頁存在本機等開始錄音才送出,
/// 會議詳情頁則直接寫回 server。
///
/// [onChanged] 收到的一律是**整組**標籤,不是差異 —— server 的 PATCH 語意就是
/// 整組覆寫,兩邊對齊才不會出現「移除一個卻把別的清掉」。
class TagEditorRow extends StatelessWidget {
  const TagEditorRow({
    super.key,
    required this.tags,
    required this.onChanged,
    this.busy = false,
    this.emptyLabel = '加標籤(讓助理更準)',
  });

  final List<String> tags;
  final ValueChanged<List<String>> onChanged;

  /// 正在寫入 server;此時停用互動並顯示轉圈圈。
  final bool busy;

  /// 還沒有任何標籤時,新增鈕上的文字。
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
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
                _TagChip(
                  label: tag,
                  onRemove: busy
                      ? null
                      : () => onChanged(
                          tags.where((t) => t != tag).toList()),
                ),
              _AddTagChip(
                // 沒有標籤時把用途說清楚,否則沒人知道這顆按鈕在做什麼。
                label: tags.isEmpty ? emptyLabel : '標籤',
                onTap: busy
                    ? null
                    : () async {
                        final picked = await showTagPicker(context, existing: tags);
                        final tag = picked?.trim();
                        if (tag == null || tag.isEmpty) return;
                        // 已經有了就不必再送一次(server 也會去重)。
                        if (tags.any((t) => t.toLowerCase() == tag.toLowerCase())) {
                          return;
                        }
                        onChanged([...tags, tag]);
                      },
              ),
              if (busy)
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
    );
  }
}

/// 開啟標籤挑選面板。回傳選/輸入的標籤;取消回 null。
Future<String?> showTagPicker(
  BuildContext context, {
  required List<String> existing,
}) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _TagPickerSheet(existing: existing),
    );

class _TagChip extends StatelessWidget {
  const _TagChip({required this.label, this.onRemove});
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

class _AddTagChip extends StatelessWidget {
  const _AddTagChip({required this.label, this.onTap});
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
