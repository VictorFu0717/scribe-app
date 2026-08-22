import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/transcript_segment.dart';
import '../providers/speaker_names_controller.dart';
import '../services/speaker_name_store.dart';

/// 說話者面板:改名(套用全部)+ 指派這一段給別人。
///
/// 兩件事放同一個面板:使用者在逐字稿上點的是「說話者 1」這個標籤,想做的不外乎
/// 「這人叫小明」(全部改名)或「這句其實是小美說的」(只改這段)。分成兩個入口
/// 反而要先想清楚自己要哪個。
class SpeakerEditSheet extends ConsumerWidget {
  const SpeakerEditSheet({
    super.key,
    required this.meetingId,
    required this.rawSegment,
    required this.index,
    required this.canonicalSpeakers,
  });

  final String meetingId;

  /// server 原始的片段(未疊過設定)—— 指派要靠它比對原始說話者。
  final TranscriptSegment rawSegment;
  final int index;

  /// 這場會議所有說話者的原始標籤 + 自建的鍵。
  final List<String> canonicalSpeakers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final prefs = ref.watch(speakerPrefsProvider(meetingId));
    final notifier = ref.read(speakerPrefsProvider(meetingId).notifier);
    final current = canonicalSpeaker(rawSegment, index, prefs);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Row(
              children: [
                const Text('這段是誰說的',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('完成'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('點名字改成該人(只影響這一段);點鉛筆改名字(套用到整場會議)。',
                style: TextStyle(fontSize: 12.5, color: scheme.outline)),
          ),
          const SizedBox(height: 8),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final canonical in canonicalSpeakers)
                  ListTile(
                    dense: true,
                    leading: Icon(
                      canonical == current
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: canonical == current
                          ? scheme.primary
                          : scheme.outline,
                      size: 20,
                    ),
                    title: Text(prefs.displayName(canonical)),
                    // 改過名的顯示原始標籤,才知道對應的是哪一位。
                    subtitle: prefs.names.containsKey(canonical) &&
                            !canonical.startsWith(SpeakerNameStore.customPrefix)
                        ? Text(canonical,
                            style: TextStyle(
                                fontSize: 11.5, color: scheme.outline))
                        : null,
                    trailing: IconButton(
                      icon: const Icon(Icons.edit_rounded, size: 18),
                      tooltip: '改名字(整場會議)',
                      onPressed: () async {
                        final name = await _askName(
                          context,
                          title: '改名字',
                          hint: '整場會議的「${prefs.displayName(canonical)}」都會改成新名字',
                          initial: prefs.displayName(canonical),
                        );
                        if (name != null) {
                          await notifier.rename(canonical, name);
                        }
                      },
                    ),
                    onTap: () => notifier.assign(rawSegment, index, canonical),
                  ),
                ListTile(
                  dense: true,
                  leading: Icon(Icons.person_add_alt_1_rounded,
                      size: 20, color: scheme.primary),
                  title: const Text('新增說話者'),
                  // diarization 會把兩個人併成一個,此時清單裡根本沒有那個人。
                  subtitle: Text('清單裡沒有這個人時使用',
                      style:
                          TextStyle(fontSize: 11.5, color: scheme.outline)),
                  onTap: () async {
                    final name = await _askName(context,
                        title: '新增說話者', hint: '例如:小美');
                    if (name == null || name.trim().isEmpty) return;
                    final key = await notifier.addSpeaker(name);
                    await notifier.assign(rawSegment, index, key);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 問一個名字。按取消或留空回 null。
  Future<String?> _askName(
    BuildContext context, {
    required String title,
    required String hint,
    String initial = '',
  }) async {
    final ctrl = TextEditingController(text: initial);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(hintText: '名字'),
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
            const SizedBox(height: 10),
            Text(hint,
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(ctx).colorScheme.outline)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('確定'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return name;
  }
}
