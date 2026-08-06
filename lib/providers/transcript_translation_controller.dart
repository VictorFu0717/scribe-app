import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/transcript_segment.dart';
import '../services/on_device_translator.dart';
import 'meeting_translation_controller.dart';

/// 已完成會議的逐字稿裝置內翻譯結果:片段 id → 譯文。
///
/// 與錄音中的即時翻譯(見 `RecordingController`)是同一套裝置內翻譯,
/// 只是套用在「事後開啟某場會議」的逐字稿上。翻譯逐段進行、逐段顯示。
final transcriptTranslationProvider = NotifierProvider.family<
    TranscriptTranslationController, Map<String, String>, String>(
  TranscriptTranslationController.new,
);

class TranscriptTranslationController
    extends FamilyNotifier<Map<String, String>, String> {
  final OnDeviceTranslatorService _translator = OnDeviceTranslatorService();

  /// 已處理過的原文(key = 片段 id);原文變動或語言改變時需重譯。
  final Map<String, String> _translatedSource = {};
  String? _langs;
  bool _running = false;

  @override
  Map<String, String> build(String meetingId) {
    ref.onDispose(() {
      _translator.dispose();
    });
    return const {};
  }

  /// 補上尚未翻譯的片段。可在每次 build 後安全重複呼叫(內部去重、單線進行)。
  Future<void> ensureTranslated(List<TranscriptSegment> segments) async {
    // 翻譯與否、用什麼語言,都由**這場會議自己的設定**決定(預設不翻)。
    final pref = ref.read(meetingTranslationProvider(arg));
    if (!pref.enabled || segments.isEmpty) return;
    if (_running) return;
    _running = true;
    try {
      final langs = '${pref.source}>${pref.target}';
      if (_langs != langs) {
        // 語言方向改了:清掉舊譯文重譯。
        _translatedSource.clear();
        state = const {};
        final ok = await _translator.prepare(pref.source, pref.target);
        if (!ok) return;
        _langs = langs;
      }

      for (final s in segments) {
        if (s.text.trim().isEmpty) continue;
        if (_translatedSource[s.id] == s.text) continue;
        final translated = await _translator.translate(s.text);
        // 失敗也記錄,避免同一段無限重試。
        _translatedSource[s.id] = s.text;
        if (translated == null) continue;
        state = {...state, s.id: translated};
      }
    } finally {
      _running = false;
    }
  }
}
