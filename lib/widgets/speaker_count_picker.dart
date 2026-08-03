import 'package:flutter/material.dart';

/// 指定說話者人數的底部選單。回傳 `-1`=自動、`2..8`=人數、`null`=取消。
///
/// 內容可捲動,避免在小螢幕上溢位(原本固定 Column 會 bottom overflow)。
Future<int?> showSpeakerCountPicker(BuildContext context) {
  return showModalBottomSheet<int>(
    context: context,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('指定說話者人數',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            ListTile(
              title: const Text('自動偵測'),
              onTap: () => Navigator.pop(ctx, -1),
            ),
            for (var n = 2; n <= 8; n++)
              ListTile(title: Text('$n 人'), onTap: () => Navigator.pop(ctx, n)),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
}
