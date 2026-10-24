import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/meeting_diagram.dart';
import 'diagram_view.dart';

/// 聊天氣泡裡的一張圖:標頭(圖種/依據)+ 圖 + 放大。
class DiagramCard extends StatelessWidget {
  const DiagramCard({super.key, required this.diagram});

  final MeetingDiagram diagram;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 4, 2),
            child: Row(
              children: [
                Icon(_icon, size: 15, color: scheme.primary),
                const SizedBox(width: 5),
                Text(diagram.kindLabel,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: scheme.primary)),
                if (diagram.sourceLabel != null) ...[
                  const SizedBox(width: 6),
                  Text(diagram.sourceLabel!,
                      style:
                          TextStyle(fontSize: 11.5, color: scheme.outline)),
                ],
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.open_in_full_rounded, size: 17),
                  tooltip: '放大檢視',
                  visualDensity: VisualDensity.compact,
                  color: scheme.outline,
                  onPressed: () => openDiagramFullScreen(context, diagram),
                ),
                IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 17),
                  tooltip: '複製原始碼',
                  visualDensity: VisualDensity.compact,
                  color: scheme.outline,
                  onPressed: () => _copy(context),
                ),
              ],
            ),
          ),
          // 整張圖可點開放大 —— 手機螢幕窄,節點一多就看不清字。
          InkWell(
            onTap: () => openDiagramFullScreen(context, diagram),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
              child: DiagramView(diagram: diagram),
            ),
          ),
          if (diagram.hint != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 13, color: scheme.outline),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(diagram.hint!,
                        style: TextStyle(
                            fontSize: 11.5, color: scheme.outline)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  IconData get _icon => switch (diagram.kind) {
        'flow' => Icons.account_tree_outlined,
        'relation' => Icons.hub_outlined,
        'timeline' => Icons.timeline_rounded,
        'mindmap' => Icons.bubble_chart_outlined,
        _ => Icons.insert_chart_outlined_rounded,
      };

  void _copy(BuildContext context) {
    Clipboard.setData(ClipboardData(text: diagram.code));
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已複製圖表原始碼(Mermaid)')));
  }
}

/// 全螢幕檢視一張圖(可縮放/平移)。
void openDiagramFullScreen(BuildContext context, MeetingDiagram diagram) {
  Navigator.of(context).push(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _DiagramFullScreen(diagram: diagram),
  ));
}

class _DiagramFullScreen extends StatelessWidget {
  const _DiagramFullScreen({required this.diagram});

  final MeetingDiagram diagram;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(diagram.kindLabel),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_rounded),
            tooltip: '複製原始碼',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: diagram.code));
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已複製圖表原始碼(Mermaid)')));
            },
          ),
        ],
      ),
      // 外層再包一層 InteractiveViewer:WebView 內的 meta viewport 允許雙指縮放,
      // 但大圖還是常常需要再拉近一點看細節。
      body: InteractiveViewer(
        maxScale: 6,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(8),
          child: DiagramView(diagram: diagram, interactive: true),
        ),
      ),
    );
  }
}
