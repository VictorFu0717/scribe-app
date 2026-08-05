import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';

import '../services/on_device_translator.dart';

/// 單一語言模型在裝置上的狀態。
enum LanguageModelState {
  /// 尚未查詢。
  unknown,

  /// 裝置上沒有,需要下載。
  absent,

  /// 正在下載(ML Kit 的下載 API 不回報進度,故只有「進行中」)。
  downloading,

  /// 已就緒,可離線翻譯。
  ready,

  /// 下載失敗(通常是網路問題),可重試。
  failed,
}

/// App 啟動時就預先準備的語言(中、英)——最常用的組合,避免開會當下才下載。
const defaultPreloadLanguages = <String>['zh', 'en'];

/// 各語言翻譯模型的下載狀態(key = 語言代碼)。
///
/// 為什麼需要:ML Kit 的語言模型約 30MB/語言,必須先下載才能離線翻譯。
/// 先前只在「開始錄音」時才下載,等於開會當下才抓幾十 MB —— 前幾句沒有譯文,
/// 還可能在行動網路下。改為 App 啟動即預載中/英,並在設定頁顯示狀態、可手動重試。
final translationModelsProvider = NotifierProvider<TranslationModelsController,
    Map<String, LanguageModelState>>(TranslationModelsController.new);

class TranslationModelsController
    extends Notifier<Map<String, LanguageModelState>> {
  final OnDeviceTranslatorModelManager _models =
      OnDeviceTranslatorModelManager();

  @override
  Map<String, LanguageModelState> build() => const {};

  LanguageModelState stateOf(String code) =>
      state[code] ?? LanguageModelState.unknown;

  void _set(String code, LanguageModelState s) {
    state = {...state, code: s};
  }

  /// 查詢指定語言是否已在裝置上(不會觸發下載)。
  Future<void> refresh(Iterable<String> codes) async {
    for (final code in codes) {
      if (state[code] == LanguageModelState.downloading) continue;
      try {
        final ready = await _models.isModelDownloaded(code);
        _set(code,
            ready ? LanguageModelState.ready : LanguageModelState.absent);
      } catch (_) {
        _set(code, LanguageModelState.unknown);
      }
    }
  }

  /// 下載指定語言模型(已存在則直接標記就緒)。
  ///
  /// 不限 Wi-Fi:會議常在外面進行,限制 Wi-Fi 會讓功能在最需要時不可用。
  Future<bool> download(String code) async {
    if (state[code] == LanguageModelState.downloading) return false;
    try {
      if (await _models.isModelDownloaded(code)) {
        _set(code, LanguageModelState.ready);
        return true;
      }
      _set(code, LanguageModelState.downloading);
      final ok = await _models.downloadModel(code, isWifiRequired: false);
      _set(code, ok ? LanguageModelState.ready : LanguageModelState.failed);
      return ok;
    } catch (_) {
      _set(code, LanguageModelState.failed);
      return false;
    }
  }

  /// 確保這些語言都在裝置上(缺的才下載)。回傳是否全部就緒。
  Future<bool> ensureDownloaded(Iterable<String> codes) async {
    var all = true;
    for (final code in codes) {
      if (!translationLanguages.containsKey(code)) continue;
      if (!await download(code)) all = false;
    }
    return all;
  }

  /// App 啟動時呼叫:在背景預先備妥中/英模型。
  ///
  /// 刻意不 await 於 UI 之前 —— 失敗也只是回到「用到才下載」,不影響 App 啟動。
  Future<void> preloadDefaults() => ensureDownloaded(defaultPreloadLanguages);
}
