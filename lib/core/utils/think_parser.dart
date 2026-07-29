/// 串流感知的 `<think>...</think>` 分離器。
///
/// 推理模型會在答案前輸出 `<think>` 區塊。由於是串流,標籤可能跨 chunk 抵達,
/// 因此需維護「是否在 think 區塊內」的狀態,逐段處理。
///
/// 用法:
/// ```dart
/// final p = ThinkParser();
/// for (final chunk in stream) {
///   p.add(chunk);
/// }
/// print(p.visible);   // 只含答案
/// print(p.thinking);  // 只含推理
/// ```
class ThinkParser {
  static const _openTag = '<think>';
  static const _closeTag = '</think>';

  final StringBuffer _visible = StringBuffer();
  final StringBuffer _thinking = StringBuffer();

  bool _inThink = false;

  /// 尚未判定完成的殘留(可能是被切斷的標籤前綴)。
  String _pending = '';

  String get visible => _visible.toString();
  String get thinking => _thinking.toString();
  bool get hasThinking => _thinking.isNotEmpty;

  void add(String chunk) {
    var buf = _pending + chunk;
    _pending = '';

    while (buf.isNotEmpty) {
      if (_inThink) {
        final close = buf.indexOf(_closeTag);
        if (close == -1) {
          // 沒有結束標籤;保留可能被切斷的尾巴。
          final keep = _suffixLenThatCouldStartTag(buf, _closeTag);
          _thinking.write(buf.substring(0, buf.length - keep));
          _pending = buf.substring(buf.length - keep);
          buf = '';
        } else {
          _thinking.write(buf.substring(0, close));
          buf = buf.substring(close + _closeTag.length);
          _inThink = false;
        }
      } else {
        final open = buf.indexOf(_openTag);
        if (open == -1) {
          final keep = _suffixLenThatCouldStartTag(buf, _openTag);
          _visible.write(buf.substring(0, buf.length - keep));
          _pending = buf.substring(buf.length - keep);
          buf = '';
        } else {
          _visible.write(buf.substring(0, open));
          buf = buf.substring(open + _openTag.length);
          _inThink = true;
        }
      }
    }
  }

  /// 收尾:把殘留當作一般可見文字(串流結束時呼叫)。
  void flush() {
    if (_pending.isNotEmpty) {
      if (_inThink) {
        _thinking.write(_pending);
      } else {
        _visible.write(_pending);
      }
      _pending = '';
    }
  }

  /// 回傳 `s` 尾端可能是 `tag` 前綴的長度(避免把被切斷的標籤誤輸出)。
  static int _suffixLenThatCouldStartTag(String s, String tag) {
    final max = s.length < tag.length - 1 ? s.length : tag.length - 1;
    for (var len = max; len > 0; len--) {
      if (tag.startsWith(s.substring(s.length - len))) return len;
    }
    return 0;
  }
}
