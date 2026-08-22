import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

/// 修改一段逐字稿的底部面板。
///
/// 做成 bottom sheet 而非對話框:鍵盤升起後仍有足夠空間,長句子也看得完整。
/// 面板內附「播放這一段」—— 改錯字時最需要的就是邊聽原音邊改。
class SegmentEditSheet extends StatefulWidget {
  const SegmentEditSheet({
    super.key,
    required this.text,
    required this.original,
    this.stamp,
    this.onPlay,
  });

  /// 目前顯示的文字(可能已是修訂過的)。
  final String text;

  /// server 的原文,用來判斷是否顯示「還原」。
  final String original;

  /// 這段的時間標記(mm:ss);沒有時間戳時為 null。
  final String? stamp;

  /// 播放這一段的原音;不可播時為 null。
  final VoidCallback? onPlay;

  @override
  State<SegmentEditSheet> createState() => _SegmentEditSheetState();
}

/// 面板的結果:[SegmentEditResult.revert] 代表要還原成原文。
class SegmentEditResult {
  const SegmentEditResult({required this.text, this.revert = false});
  final String text;
  final bool revert;
}

class _SegmentEditSheetState extends State<SegmentEditSheet> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.text);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isEdited = widget.text != widget.original;
    return Padding(
      // 讓面板隨鍵盤上推,否則輸入框會被鍵盤蓋住。
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('修改逐字稿',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              if (widget.stamp != null) ...[
                const SizedBox(width: 8),
                Text(widget.stamp!,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: scheme.outline,
                    )),
              ],
              const Spacer(),
              if (widget.onPlay != null)
                TextButton.icon(
                  onPressed: widget.onPlay,
                  icon: const Icon(Icons.play_arrow_rounded, size: 20),
                  label: const Text('聽這段'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 34),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _ctrl,
            autofocus: true,
            maxLines: 6,
            minLines: 3,
            textInputAction: TextInputAction.newline,
            keyboardType: TextInputType.multiline,
            style: const TextStyle(fontSize: 15, height: 1.5),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding: EdgeInsets.all(12),
            ),
          ),
          if (isEdited) ...[
            const SizedBox(height: 8),
            // 顯示原文,才知道自己改了什麼、也才有還原的依據。
            Text('原文:${widget.original}',
                style: TextStyle(fontSize: 12.5, color: scheme.outline),
                maxLines: 3,
                overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              if (isEdited)
                TextButton(
                  onPressed: () => Navigator.pop(
                      context,
                      SegmentEditResult(
                          text: widget.original, revert: true)),
                  child: const Text('還原原文'),
                ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              const SizedBox(width: 4),
              FilledButton(
                onPressed: () => Navigator.pop(
                    context, SegmentEditResult(text: _ctrl.text)),
                child: const Text('儲存'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('修改只存在這支手機。server 端的摘要與 AI 助理仍會用原始的辨識結果。',
              style: TextStyle(fontSize: 11.5, color: scheme.outline)),
        ],
      ),
    );
  }
}
