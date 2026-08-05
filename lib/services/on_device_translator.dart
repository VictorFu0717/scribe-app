import 'package:google_mlkit_translation/google_mlkit_translation.dart';

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
      final result = out.trim();
      return result.isEmpty ? null : result;
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
    if (t != null) {
      try {
        await t.close();
      } catch (_) {}
    }
  }
}
