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
  });

  final List<TranscriptSegment> segments;
  final TranscriptSegment? partial;
  final bool autoScroll;
  final EdgeInsets padding;
  final String emptyHint;

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
        return _SegmentTile(segment: seg, dimmed: isPartial);
      },
    );
  }
}

class _SegmentTile extends StatelessWidget {
  const _SegmentTile({required this.segment, this.dimmed = false});
  final TranscriptSegment segment;
  final bool dimmed;

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
        ],
      ),
    );
  }
}
