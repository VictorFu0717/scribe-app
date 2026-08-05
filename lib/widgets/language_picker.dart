import 'package:flutter/material.dart';

import '../services/on_device_translator.dart';

/// 選擇翻譯語言。`exclude` 為對向語言(來源/目標不可相同,故從清單移除)。
/// 回傳語言代碼;取消回 null。
Future<String?> showLanguagePicker(
  BuildContext context, {
  required String title,
  required String current,
  String? exclude,
}) {
  final codes = translationLanguages.keys.where((c) => c != exclude).toList();
  return showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(title),
      children: [
        for (final code in codes)
          RadioListTile<String>(
            value: code,
            groupValue: current,
            title: Text(translationLanguageLabel(code)),
            onChanged: (v) => Navigator.of(ctx).pop(v),
          ),
      ],
    ),
  );
}
