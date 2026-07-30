import 'package:flutter/material.dart';

import '../core/theme/app_style.dart';

/// 「匯出 .txt」按鈕。點擊時把自身在畫面上的位置(iPad 分享面板錨點)回傳給
/// [onExport],由呼叫端執行實際匯出。
class ExportButton extends StatelessWidget {
  const ExportButton({
    super.key,
    required this.onExport,
    this.label = '匯出 .txt',
  });

  final void Function(Rect? shareOrigin) onExport;
  final String label;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => onExport(_origin(context)),
      icon: const Icon(Icons.save_alt_rounded, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppStyle.rXl)),
      ),
    );
  }

  static Rect? _origin(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }
}
