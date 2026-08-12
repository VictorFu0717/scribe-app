import 'dart:ui' show FontFeature;

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
    this.onSeek,
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
  });
  final TranscriptSegment segment;
  final bool dimmed;
  final void Function(Duration position)? onSeek;

  /// 把毫秒格式成 mm:ss(超過一小時才顯示小時),與播放器的時間軸一致。
  static String formatStamp(int ms) {
    final d = Duration(milliseconds: ms);
    String two(int n) => n.toString().padLeft(2, '0');
    final m = two(d.inMinutes.remainder(60));
    final s = two(d.inSeconds.remainder(60));
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

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
                          formatStamp(startMs),
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
                ],
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
