import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/upload_progress_controller.dart';

/// 整檔上傳的進度對話框:進度條 + 百分比 + 已傳/總量。
///
/// 由「上傳音檔」、「從其他 App 分享進來」、「重新轉錄」共用 —— 上傳一小時的錄音
/// 要好幾分鐘,先前只有一顆轉圈圈,使用者無從判斷是在跑還是卡住。
class UploadProgressDialog extends ConsumerWidget {
  const UploadProgressDialog({super.key, this.title});

  /// 標題;省略時依階段自動顯示。
  final String? title;

  static String _label(UploadPhase phase) => switch (phase) {
        UploadPhase.preparing => '準備中…',
        UploadPhase.uploading => '上傳中…',
        // 位元組送完但 server 還要存檔並建立轉錄工作,這段沒有進度可報。
        UploadPhase.processing => 'server 接收中…',
        UploadPhase.compressing => '壓縮本機錄音檔…',
        UploadPhase.idle => '處理中…',
      };

  /// 位元組轉成人看得懂的大小。上傳中的錄音檔動輒上百 MB。
  static String formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(uploadProgressProvider);
    final scheme = Theme.of(context).colorScheme;
    final percent = st.percent;
    final showPercent = st.phase == UploadPhase.uploading && percent != null;

    return AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title ?? _label(st.phase),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              if (showPercent)
                Text('$percent%',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, color: scheme.primary)),
            ],
          ),
          const SizedBox(height: 12),
          // 上傳階段用確定進度;其餘階段沒有可靠的百分比,用不確定樣式才誠實。
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: showPercent ? st.fraction : null,
              minHeight: 7,
            ),
          ),
          if (showPercent) ...[
            const SizedBox(height: 8),
            Text('${formatBytes(st.sent)} / ${formatBytes(st.total)}',
                style: TextStyle(fontSize: 12, color: scheme.outline)),
          ],
          const SizedBox(height: 10),
          Text(
            st.phase == UploadPhase.compressing
                ? '壓縮後才方便用通訊軟體傳給別人,請稍候。'
                : '長時間的錄音需要上傳與處理,請暫時不要切換到其他 App。',
            style: TextStyle(fontSize: 12.5, color: scheme.outline),
          ),
        ],
      ),
    );
  }
}
