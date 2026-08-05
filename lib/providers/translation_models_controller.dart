import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';

import '../services/on_device_translator.dart';

/// 單一語言模型在裝置上的狀態。
enum LanguageModelState {
  /// 尚未查詢完成。
  unknown,

  /// 裝置上沒有,需要下載。
  absent,

  /// 正在下載(ML Kit 的下載 API 不回報進度,故只有「進行中」)。
  downloading,

  /// 已就緒,可離線翻譯。
  ready,

  /// 查詢或下載失敗,可重試(詳細原因見 [LanguageModelStatus.error])。
  failed,
}

/// 語言模型狀態 + 失敗原因。
///
/// 保留 [error] 是刻意的:先前把例外靜默吞掉,使用者只看到「檢查中…」卻不知原因,
/// 除錯時也無從判斷。原因直接顯示在設定頁。
class LanguageModelStatus {
  const LanguageModelStatus(this.state, {this.error});
  final LanguageModelState state;
  final String? error;
}

/// App 啟動時就預先準備的語言(中、英)——最常用的組合,避免開會當下才下載。
const defaultPreloadLanguages = <String>['zh', 'en'];

/// 查詢/下載的逾時:避免 method channel 沒回應時 UI 永遠停在「檢查中…」。
const _opTimeout = Duration(seconds: 30);

/// 各語言翻譯模型的狀態(key = 語言代碼)。
///
/// ML Kit 的語言模型約 30MB/語言,必須先下載才能離線翻譯。App 啟動即預載中/英,
/// 並在設定頁顯示狀態與失敗原因、可手動重試。
final translationModelsProvider = NotifierProvider<TranslationModelsController,
    Map<String, LanguageModelStatus>>(TranslationModelsController.new);

class TranslationModelsController
    extends Notifier<Map<String, LanguageModelStatus>> {
  final OnDeviceTranslatorModelManager _models =
      OnDeviceTranslatorModelManager();

  @override
  Map<String, LanguageModelStatus> build() => const {};

  LanguageModelStatus statusOf(String code) =>
      state[code] ?? const LanguageModelStatus(LanguageModelState.unknown);

  void _set(String code, LanguageModelState s, [Object? error]) {
    state = {
      ...state,
      code: LanguageModelStatus(s, error: error == null ? null : _msg(error)),
    };
  }

  static String _msg(Object e) {
    final s = e.toString();
    return s.length > 160 ? '${s.substring(0, 160)}…' : s;
  }

  /// 查詢指定語言是否已在裝置上(不觸發下載)。
  Future<void> refresh(Iterable<String> codes) async {
    for (final code in codes) {
      if (state[code]?.state == LanguageModelState.downloading) continue;
      try {
        final ready =
            await _models.isModelDownloaded(code).timeout(_opTimeout);
        _set(code,
            ready ? LanguageModelState.ready : LanguageModelState.absent);
      } on TimeoutException {
        _set(code, LanguageModelState.failed, '查詢逾時(超過 30 秒沒有回應)');
      } catch (e) {
        _set(code, LanguageModelState.failed, e);
      }
    }
  }

  /// 下載指定語言模型(已存在則直接標記就緒)。
  ///
  /// 不限 Wi-Fi:會議常在外面進行,限制 Wi-Fi 會讓功能在最需要時不可用。
  Future<bool> download(String code) async {
    if (state[code]?.state == LanguageModelState.downloading) return false;
    try {
      if (await _models.isModelDownloaded(code).timeout(_opTimeout)) {
        _set(code, LanguageModelState.ready);
        return true;
      }
      _set(code, LanguageModelState.downloading);
      // 下載大檔給較長時間(30MB 在慢速網路可能要幾分鐘)。
      final ok = await _models
          .downloadModel(code, isWifiRequired: false)
          .timeout(const Duration(minutes: 10));
      if (ok) {
        _set(code, LanguageModelState.ready);
      } else {
        _set(code, LanguageModelState.failed, 'ML Kit 回報下載未成功');
      }
      return ok;
    } on TimeoutException {
      _set(code, LanguageModelState.failed, '下載逾時');
      return false;
    } catch (e) {
      _set(code, LanguageModelState.failed, e);
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
