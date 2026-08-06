import 'package:google_mlkit_translation/google_mlkit_translation.dart';

import 'chinese_convert.dart';

/// 可選的翻譯語言(ML Kit 裝置內翻譯 ∩ server 留檔翻譯常用語言)。
///
/// 來源與目標都從此清單選,因此含中文 —— 中→英、**英→中**、中→日 皆可。
const translationLanguages = <String, String>{
  'zh': '中文',
  'en': '英文',
  'ja': '日文',
  'ko': '韓文',
  'vi': '越南文',
  'id': '印尼文',
  'th': '泰文',
  'es': '西班牙文',
  'fr': '法文',
  'de': '德文',
  'ru': '俄文',
};

String translationLanguageLabel(String code) =>
    translationLanguages[code] ?? code;

/// 粗略判斷一段文字是否以中文為主(CJK 漢字多於拉丁字母)。
///
/// 用於「沒有記錄翻譯方向」的會議(匯入的音檔、舊資料):若逐字稿語言與設定的
/// 來源語言不符,直接照設定翻會得到垃圾結果(例如把英文當中文翻成英文)。
bool looksChinese(String text) {
  var cjk = 0;
  var latin = 0;
  for (final r in text.runes) {
    if (r >= 0x4E00 && r <= 0x9FFF) {
      cjk++;
    } else if ((r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A)) {
      latin++;
    }
  }
  return cjk > latin;
}

/// 依逐字稿內容決定實際該用的翻譯方向。
///
/// 規則:只在「設定的其中一邊是中文」時才可能修正 —— 若逐字稿明顯是中文卻被設成
/// 目標語言(或反之),就把方向反過來。其他語言組合無從判斷,維持使用者設定。
({String source, String target}) resolveDirection({
  required String sampleText,
  required String source,
  required String target,
}) {
  if (sampleText.trim().isEmpty) return (source: source, target: target);
  final isChinese = looksChinese(sampleText);
  // 逐字稿是中文,但設定成「翻譯目標是中文」→ 方向反了。
  if (isChinese && target == 'zh' && source != 'zh') {
    return (source: target, target: source);
  }
  // 逐字稿不是中文,但設定成「來源是中文」→ 方向反了。
  if (!isChinese && source == 'zh' && target != 'zh') {
    return (source: target, target: source);
  }
  return (source: source, target: target);
}

/// 裝置內即時翻譯:錄音時把每句**定稿**逐字稿翻成目標語言,做雙語字幕。
///
/// 用裝置內翻譯(而非呼叫 server)的原因:零延遲、離線可用、不增加 server 負載。
/// 會後整篇的高品質翻譯走 server `POST /meetings/{id}/translate`(見 backend)。
///
/// 首次使用某語言需下載語言模型(約 30MB);下載後永久離線可用。
class OnDeviceTranslatorService {
  OnDeviceTranslator? _translator;
  String? _readySource;
  String? _readyTarget;
  final OnDeviceTranslatorModelManager _models =
      OnDeviceTranslatorModelManager();

  /// 目標是中文時需把 ML Kit 的簡體輸出轉成繁體(台灣)。
  bool _toTraditional = false;

  /// 目前是否已可翻譯。
  bool get isReady => _translator != null;

  /// 準備「來源 → 目標」的翻譯器,必要時下載語言模型。回傳是否可用。
  ///
  /// 同一組語言重複呼叫會沿用既有翻譯器(不重複下載)。
  /// 來源與目標相同則視為不需翻譯,回 false。
  Future<bool> prepare(String sourceCode, String targetCode) async {
    if (sourceCode == targetCode) return false;
    if (_readySource == sourceCode &&
        _readyTarget == targetCode &&
        _translator != null) {
      return true;
    }

    // fromRawValue 是 extension BCP47Code 的 static,需以 extension 名稱呼叫。
    final source = BCP47Code.fromRawValue(sourceCode);
    final target = BCP47Code.fromRawValue(targetCode);
    if (source == null || target == null || source == target) return false;

    await _closeTranslator();

    try {
      // 來源與目標語言模型都要在裝置上。
      for (final lang in [source, target]) {
        final code = lang.bcpCode;
        if (!await _models.isModelDownloaded(code)) {
          // isWifiRequired: false —— 會議常在外面進行,不該只限 Wi-Fi 才能啟用。
          final ok = await _models.downloadModel(code, isWifiRequired: false);
          if (!ok) return false;
        }
      }
      // ML Kit 的中文只有簡體;目標是中文就要再轉繁體(台灣)。
      _toTraditional = target == TranslateLanguage.chinese;
      if (_toTraditional) await ChineseConvert.ensureLoaded();

      _translator = OnDeviceTranslator(
        sourceLanguage: source,
        targetLanguage: target,
      );
      _readySource = sourceCode;
      _readyTarget = targetCode;
      return true;
    } catch (_) {
      await _closeTranslator();
      return false;
    }
  }

  /// 翻譯一段文字;未就緒或失敗回 null(呼叫端保留原文即可)。
  Future<String?> translate(String text) async {
    final t = _translator;
    if (t == null) return null;
    final src = text.trim();
    if (src.isEmpty) return null;
    try {
      final out = await t.translateText(src);
      var result = out.trim();
      if (result.isEmpty) return null;
      // ML Kit 只輸出簡體中文,轉成繁體(台灣正體 + 用語)。
      if (_toTraditional) result = ChineseConvert.s2twp(result);
      return result;
    } catch (_) {
      return null;
    }
  }

  Future<void> dispose() => _closeTranslator();

  Future<void> _closeTranslator() async {
    final t = _translator;
    _translator = null;
    _readySource = null;
    _readyTarget = null;
    _toTraditional = false;
    if (t != null) {
      try {
        await t.close();
      } catch (_) {}
    }
  }
}
