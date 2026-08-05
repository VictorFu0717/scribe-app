import 'package:flutter/services.dart';

/// 簡體中文 → 繁體中文(台灣正體,含台灣用語轉換)。
///
/// 為什麼需要:裝置內翻譯(ML Kit)的中文只有簡體(`zh`),沒有繁體選項,
/// 所以「英→中」的譯文會是簡體,需要再轉一次。
///
/// 為什麼自己實作而不用 opencc 套件:現有 Flutter 套件都帶 native C++(需 NDK)
/// 或實驗性 native-assets,增加跨平台編譯風險。此處改用 OpenCC 的**字典資料**
/// (assets/dict/s2twp.txt)配純 Dart 最長匹配,品質相同且零編譯風險。
///
/// 字典為 OpenCC `s2twp` 的三階段合併(STPhrases + STCharacters → 台灣用語 → 正體變體)。
/// STPhrases 已濾掉「字元級轉換即可得到相同結果」的詞條(49041 → 9866),
/// 只留下會造成歧義的(例如 头发→頭髮 而非 頭發),故體積由 1MB 降至 ~234KB。
class ChineseConvert {
  ChineseConvert._();

  static const _assetPath = 'assets/dict/s2twp.txt';

  static Map<String, String>? _s2t; // 階段一:簡 → 繁
  static Map<String, String>? _tw; // 階段二:台灣用語 + 正體變體
  static int _s2tMaxLen = 1;
  static int _twMaxLen = 1;
  static Future<void>? _loading;

  /// 是否已可轉換。
  static bool get isReady => _s2t != null;

  /// 載入字典(冪等;併發呼叫共用同一次載入)。
  static Future<void> ensureLoaded() {
    if (_s2t != null) return Future.value();
    return _loading ??= _load();
  }

  static Future<void> _load() async {
    try {
      final raw = await rootBundle.loadString(_assetPath);
      final s2t = <String, String>{};
      final tw = <String, String>{};
      var target = s2t;
      var s2tMax = 1;
      var twMax = 1;

      for (final line in raw.split('\n')) {
        if (line.isEmpty) continue;
        if (line.startsWith('#')) {
          target = line.startsWith('#TW') ? tw : s2t;
          continue;
        }
        final tab = line.indexOf('\t');
        if (tab <= 0) continue;
        final key = line.substring(0, tab);
        final value = line.substring(tab + 1);
        if (key.isEmpty || value.isEmpty) continue;
        target[key] = value;
        if (identical(target, s2t)) {
          if (key.length > s2tMax) s2tMax = key.length;
        } else {
          if (key.length > twMax) twMax = key.length;
        }
      }

      _s2t = s2t;
      _tw = tw;
      _s2tMaxLen = s2tMax;
      _twMaxLen = twMax;
    } catch (_) {
      // 載入失敗就維持未就緒:轉換會原樣回傳,不影響翻譯本身。
    } finally {
      _loading = null;
    }
  }

  /// 簡體 → 繁體(台灣)。字典未就緒時原樣回傳。
  static String s2twp(String input) {
    final s2t = _s2t;
    final tw = _tw;
    if (s2t == null || tw == null || input.isEmpty) return input;
    return _apply(_apply(input, s2t, _s2tMaxLen), tw, _twMaxLen);
  }

  /// 最長匹配替換(詞優先於字)。
  static String _apply(String s, Map<String, String> dict, int maxLen) {
    final out = StringBuffer();
    var i = 0;
    while (i < s.length) {
      var matched = false;
      var maxTry = maxLen;
      if (i + maxTry > s.length) maxTry = s.length - i;
      for (var len = maxTry; len >= 1; len--) {
        final hit = dict[s.substring(i, i + len)];
        if (hit != null) {
          out.write(hit);
          i += len;
          matched = true;
          break;
        }
      }
      if (!matched) {
        // 未命中:原樣輸出一個完整字元(避免切開 surrogate pair 造成亂碼)。
        final unit = s.codeUnitAt(i);
        final isHighSurrogate = unit >= 0xD800 && unit <= 0xDBFF;
        final step = (isHighSurrogate && i + 1 < s.length) ? 2 : 1;
        out.write(s.substring(i, i + step));
        i += step;
      }
    }
    return out.toString();
  }
}
