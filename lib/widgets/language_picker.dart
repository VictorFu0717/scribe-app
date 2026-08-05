import 'package:flutter/material.dart';

import '../services/on_device_translator.dart';

/// 選擇翻譯語言。
///
/// 刻意**不隱藏**任何語言(含對向語言):若選到與對向相同,呼叫端會自動交換方向。
/// 先前隱藏對向語言會造成「中→英」時來源清單裡找不到英文,無法改成「英→中」。
/// 回傳語言代碼;取消回 null。
Future<String?> showLanguagePicker(
  BuildContext context, {
  required String title,
  required String current,
}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(title),
      children: [
        for (final code in translationLanguages.keys)
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
