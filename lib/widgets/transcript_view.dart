import 'package:flutter/material.dart';

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
  });

  final List<TranscriptSegment> segments;
  final TranscriptSegment? partial;
  final bool autoScroll;
  final EdgeInsets padding;
  final String emptyHint;

  /// 片段 id → 譯文(裝置內即時翻譯)。有值時在原文下方顯示譯文。
  final Map<String, String> translations;

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
  });
  final TranscriptSegment segment;
  final bool dimmed;

  /// 裝置內翻譯的譯文;null 表示無(未開翻譯、尚未譯出或翻譯失敗)。
  final String? translation;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (segment.speaker != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                segment.speaker!,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: scheme.primary,
                ),
              ),
            ),
          Text(
            segment.text,
            style: TextStyle(
              fontSize: 15,
              height: 1.5,
              color: dimmed ? scheme.outline : scheme.onSurface,
              fontStyle: dimmed ? FontStyle.italic : FontStyle.normal,
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
