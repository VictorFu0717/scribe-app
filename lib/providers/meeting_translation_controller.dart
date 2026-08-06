import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'service_providers.dart';
import 'settings_controller.dart';

/// 單一會議的翻譯設定(是否翻譯 + 語言方向),以 meetingId 為 key。
///
/// 預設**不翻譯** —— 多數會議不需要翻譯,不該一開全域開關就把所有會議都翻一遍
/// (既浪費時間,語言不符時還會翻出垃圾)。錄音時若啟用了即時翻譯,結束後會把
/// 該場設為已啟用並記下方向;其餘會議由使用者在會議詳情頁自行開啟。
final meetingTranslationProvider = NotifierProvider.family<
    MeetingTranslationController, MeetingTranslationPref, String>(
  MeetingTranslationController.new,
);

class MeetingTranslationController
    extends FamilyNotifier<MeetingTranslationPref, String> {
  @override
  MeetingTranslationPref build(String meetingId) {
    final saved = ref.read(meetingTranslationStoreProvider).prefFor(meetingId);
    if (saved != null) return saved;
    // 沒有記錄:預設關閉,語言沿用全域設定當起始值。
    final s = ref.read(settingsProvider);
    return MeetingTranslationPref(
      enabled: false,
      source: s.translationSource,
      target: s.translationTarget,
    );
  }

  Future<void> _persist(MeetingTranslationPref pref) async {
    state = pref;
    await ref.read(meetingTranslationStoreProvider).save(arg, pref);
  }

  Future<void> setEnabled(bool enabled) =>
      _persist(state.copyWith(enabled: enabled));

  /// 設定語言。選到與對向相同時自動交換(不讓使用者卡在無效狀態)。
  Future<void> setLanguages({String? source, String? target}) {
    var src = source ?? state.source;
    var tgt = target ?? state.target;
    if (src == tgt) {
      if (source != null) {
        tgt = state.source;
      } else {
        src = state.target;
      }
    }
    if (src == tgt) return Future.value();
    return _persist(state.copyWith(source: src, target: tgt));
  }

  Future<void> swap() =>
      _persist(state.copyWith(source: state.target, target: state.source));
}
