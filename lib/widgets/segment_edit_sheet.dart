import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

/// 修改一段逐字稿的底部面板。
///
/// 做成 bottom sheet 而非對話框:鍵盤升起後仍有足夠空間,長句子也看得完整。
/// 面板內附「聽這段」—— 改錯字時最需要的就是邊聽原音邊改。
///
/// 「取消 / 儲存」放在**最上面**而不是底部:鍵盤高度差異很大(中文輸入法多一排
/// 候選字,比英文鍵盤高出近百點),放底部就得賭空間夠不夠。放頂端則永遠蓋不到。
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
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(scheme),
          const Divider(height: 1),
          // 內容可捲動:鍵盤很高又遇上長句子時,才不會有東西完全摸不到。
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _ctrl,
                    autofocus: true,
                    maxLines: null,
                    minLines: 3,
                    keyboardType: TextInputType.multiline,
                    textCapitalization: TextCapitalization.sentences,
                    style: const TextStyle(fontSize: 15, height: 1.5),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.all(12),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      if (widget.onPlay != null)
                        TextButton.icon(
                          onPressed: widget.onPlay,
                          icon: const Icon(Icons.play_arrow_rounded, size: 20),
                          label: const Text('聽這段'),
                          style: _compact,
                        ),
                      const Spacer(),
                      if (isEdited)
                        TextButton(
                          onPressed: () => Navigator.pop(
                            context,
                            SegmentEditResult(
                                text: widget.original, revert: true),
                          ),
                          style: _compact,
                          child: const Text('還原原文'),
                        ),
                    ],
                  ),
                  if (isEdited) ...[
                    const SizedBox(height: 4),
                    // 顯示原文,才知道自己改了什麼、也才有還原的依據。
                    Text('原文:${widget.original}',
                        style:
                            TextStyle(fontSize: 12.5, color: scheme.outline)),
                  ],
                  const SizedBox(height: 10),
                  Text('修改只存在這支手機。server 端的摘要與 AI 助理仍會用原始的辨識結果。',
                      style:
                          TextStyle(fontSize: 11.5, color: scheme.outline)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static final ButtonStyle _compact = TextButton.styleFrom(
    padding: const EdgeInsets.symmetric(horizontal: 10),
    minimumSize: const Size(0, 36),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );

  Widget _header(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
      child: Row(
        children: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: _compact,
            child: const Text('取消'),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('修改逐字稿',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                if (widget.stamp != null) ...[
                  const SizedBox(width: 6),
                  Text(widget.stamp!,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: scheme.outline,
                      )),
                ],
              ],
            ),
          ),
          // **一定要給 minimumSize**:App 主題把所有 FilledButton 設成
          // Size.fromHeight(54)(寬度 = infinity,為了讓表單按鈕滿版)。放進 Row
          // 會變成「強制無限寬」—— debug 版直接拋 assertion,release 版不報錯但
          // 按鈕被排到畫面外,實測就是「找不到儲存按鈕」。
          FilledButton(
            onPressed: () => Navigator.pop(
                context, SegmentEditResult(text: _ctrl.text)),
            style: FilledButton.styleFrom(
              minimumSize: const Size(64, 38),
              padding: const EdgeInsets.symmetric(horizontal: 18),
              textStyle:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            child: const Text('儲存'),
          ),
        ],
      ),
    );
  }
}
