import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../core/utils/formatters.dart';
import '../models/transcript_segment.dart';

/// 逐字稿檢視。可帶一個暫定片段(邊錄邊出);live 模式自動捲到底。
class TranscriptView extends StatefulWidget {
  const TranscriptView({
    super.key,
    required this.segments,
    this.partial,
    this.autoScroll = false,
    this.padding = const EdgeInsets.all(16),
    this.emptyHint = '尚無逐字稿',
    this.translations = const {},
    this.onSeek,
    this.onEdit,
    this.editedKeys = const {},
  });

  final List<TranscriptSegment> segments;
  final TranscriptSegment? partial;
  final bool autoScroll;
  final EdgeInsets padding;
  final String emptyHint;

  /// 片段 id → 譯文(裝置內即時翻譯)。有值時在原文下方顯示譯文。
  final Map<String, String> translations;

  /// 點時間戳時跳到錄音的該位置。給定時才顯示可點擊的時間標記 ——
  /// 用途是「發現某句辨識有誤,直接跳回去聽原音對照」。
  final void Function(Duration position)? onSeek;

  /// 點文字時修改該段(辨識有誤時自行改正)。給定時文字才可點。
  ///
  /// 帶 index 是因為修訂的 key 在沒有時間戳時要靠位置(見 TranscriptEditStore)。
  final void Function(TranscriptSegment segment, int index)? onEdit;

  /// 已被修改過的片段索引,用來標示「已編輯」。
  final Set<int> editedKeys;

  @override
  State<TranscriptView> createState() => _TranscriptViewState();
}

class _TranscriptViewState extends State<TranscriptView> {
  final _scrollCtrl = ScrollController();

  @override
  void didUpdateWidget(TranscriptView old) {
    super.didUpdateWidget(old);
    if (widget.autoScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollCtrl.hasClients) {
          _scrollCtrl.animateTo(
            _scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = [
      ...widget.segments,
      if (widget.partial != null) widget.partial!,
    ];
    if (items.isEmpty) {
      return Center(
        child: Text(widget.emptyHint,
            style: TextStyle(color: Theme.of(context).colorScheme.outline)),
      );
    }
    return ListView.builder(
      controller: _scrollCtrl,
      padding: widget.padding,
      itemCount: items.length,
      itemBuilder: (_, i) {
        final seg = items[i];
        final isPartial = !seg.isFinal;
        return _SegmentTile(
          segment: seg,
          dimmed: isPartial,
          // 暫定片段不顯示譯文(文字還會變),只翻定稿。
          translation: isPartial ? null : widget.translations[seg.id],
          onSeek: isPartial ? null : widget.onSeek,
          // 暫定片段不給編輯:文字下一秒就會被 server 的定稿覆蓋。
          onEdit: isPartial || widget.onEdit == null
              ? null
              : () => widget.onEdit!(seg, i),
          edited: widget.editedKeys.contains(i),
        );
      },
    );
  }
}

class _SegmentTile extends StatelessWidget {
  const _SegmentTile({
    required this.segment,
    this.dimmed = false,
    this.translation,
    this.onSeek,
    this.onEdit,
    this.edited = false,
  });
  final TranscriptSegment segment;
  final bool dimmed;
  final void Function(Duration position)? onSeek;

  /// 點文字修改這一段;null 表示不可編輯。
  final VoidCallback? onEdit;

  /// 這段已被人工修改過(標示出來,才知道哪裡動過)。
  final bool edited;

  /// 裝置內翻譯的譯文;null 表示無(未開翻譯、尚未譯出或翻譯失敗)。
  final String? translation;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final startMs = segment.startMs;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (segment.speaker != null || startMs != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                children: [
                  if (startMs != null) ...[
                    // 可點擊 → 跳到錄音的該位置(辨識有誤時回去對照原音)。
                    InkWell(
                      onTap: onSeek == null
                          ? null
                          : () => onSeek!(Duration(milliseconds: startMs)),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                        child: Text(
                          Formatters.duration(
                              Duration(milliseconds: startMs)),
                          style: TextStyle(
                            fontSize: 11.5,
                            fontFeatures: const [FontFeature.tabularFigures()],
                            fontWeight: FontWeight.w600,
                            color: onSeek == null
                                ? scheme.outline
                                : scheme.primary,
                            decoration: onSeek == null
                                ? null
                                : TextDecoration.underline,
                            decorationColor: scheme.primary.withValues(alpha: 0.4),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  if (segment.speaker != null)
                    Text(
                      segment.speaker!,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: scheme.primary,
                      ),
                    ),
                  if (edited) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.edit_rounded,
                        size: 11, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 2),
                    Text('已編輯',
                        style: TextStyle(
                            fontSize: 11, color: scheme.onSurfaceVariant)),
                  ],
                ],
              ),
            ),
          // 點文字 → 修改這一段(辨識有誤時自行改正)。
          //
          // 用 InkWell 包住而非改成 TextField:逐字稿是長列表,每段都放
          // TextField 會讓捲動與焦點都變得不穩;點開後才進編輯畫面。
          InkWell(
            onTap: onEdit,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
              child: Text(
                segment.text,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  color: dimmed ? scheme.outline : scheme.onSurface,
                  fontStyle: dimmed ? FontStyle.italic : FontStyle.normal,
                ),
              ),
            ),
          ),
          // 譯文:左側細線 + 次要色,與原文區分但同一段落。
          if (translation != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Container(
                padding: const EdgeInsets.only(left: 8),
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: scheme.primary.withValues(alpha: 0.4), width: 2),
                  ),
                ),
                child: Text(
                  translation!,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
