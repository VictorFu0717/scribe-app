import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/app_config.dart';

/// 執行期使用者設定(持久化於 SharedPreferences)。
///
/// App 只連 scribe server 這**單一入口**(一個對外 port);所有 AI/ML(ASR、LLM、
/// RAG)都在 server 內部處理,client 不直連任何模型服務。
class Settings {
  const Settings({
    required this.baseUrl,
    required this.useMock,
    required this.diarization,
    this.speakerCount,
    required this.requireLogin,
    required this.keepScreenOn,
    required this.translationEnabled,
    required this.translationSource,
    required this.translationTarget,
  });

  /// scribe server base URL(唯一對外入口)。負責 auth、會議、轉錄、摘要、助理。
  final String baseUrl;

  /// 是否使用內建 mock 後端。
  final bool useMock;

  /// diarization 預設開關。
  final bool diarization;

  /// 指定說話者人數(null = 自動)。
  final int? speakerCount;

  /// 是否需要登入(關閉時 dev 直接進入,適用尚未做 auth 的後端)。
  final bool requireLogin;

  /// 錄音時螢幕常亮(避免自動鎖屏 → App 被 iOS 暫停而中斷長時間背景錄音)。
  final bool keepScreenOn;

  /// 是否開啟翻譯(即時雙語字幕 + 會後整篇留檔翻譯)。
  final bool translationEnabled;

  /// 翻譯來源語言代碼(逐字稿的語言),例如 'zh' / 'en'。
  final String translationSource;

  /// 翻譯目標語言代碼,例如 'en' / 'zh'。
  final String translationTarget;

  Settings copyWith({
    String? baseUrl,
    bool? useMock,
    bool? diarization,
    int? speakerCount,
    bool clearSpeakerCount = false,
    bool? requireLogin,
    bool? keepScreenOn,
    bool? translationEnabled,
    String? translationSource,
    String? translationTarget,
  }) {
    return Settings(
      baseUrl: baseUrl ?? this.baseUrl,
      useMock: useMock ?? this.useMock,
      diarization: diarization ?? this.diarization,
      speakerCount:
          clearSpeakerCount ? null : (speakerCount ?? this.speakerCount),
      requireLogin: requireLogin ?? this.requireLogin,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
      translationEnabled: translationEnabled ?? this.translationEnabled,
      translationSource: translationSource ?? this.translationSource,
      translationTarget: translationTarget ?? this.translationTarget,
    );
  }
}

/// 需在 main() 以實際 SharedPreferences 覆寫。
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('須在 main() override sharedPreferencesProvider'),
);

final settingsProvider =
    NotifierProvider<SettingsController, Settings>(SettingsController.new);

class SettingsController extends Notifier<Settings> {
  static const _kBaseUrl = 'settings.base_url';
  static const _kUseMock = 'settings.use_mock';
  static const _kDiarization = 'settings.diarization';
  static const _kSpeakerCount = 'settings.speaker_count';
  static const _kRequireLogin = 'settings.require_login';
  static const _kKeepScreenOn = 'settings.keep_screen_on';
  static const _kTranslationEnabled = 'settings.translation_enabled';
  static const _kTranslationSource = 'settings.translation_source';
  static const _kTranslationTarget = 'settings.translation_target';

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  Settings build() {
    final p = _prefs;
    return Settings(
      baseUrl: p.getString(_kBaseUrl) ?? AppConfig.defaultApiBaseUrl,
      useMock: p.getBool(_kUseMock) ?? AppConfig.defaultUseMock,
      diarization: p.getBool(_kDiarization) ?? false,
      speakerCount:
          p.containsKey(_kSpeakerCount) ? p.getInt(_kSpeakerCount) : null,
      requireLogin: p.getBool(_kRequireLogin) ?? true,
      keepScreenOn: p.getBool(_kKeepScreenOn) ?? true,
      translationEnabled: p.getBool(_kTranslationEnabled) ?? false,
      translationSource: p.getString(_kTranslationSource) ?? 'zh',
      translationTarget: p.getString(_kTranslationTarget) ?? 'en',
    );
  }

  Future<void> setBaseUrl(String url) async {
    await _prefs.setString(_kBaseUrl, url.trim());
    state = state.copyWith(baseUrl: url.trim());
  }

  Future<void> setUseMock(bool value) async {
    await _prefs.setBool(_kUseMock, value);
    state = state.copyWith(useMock: value);
  }

  Future<void> setDiarization(bool value) async {
    await _prefs.setBool(_kDiarization, value);
    state = state.copyWith(diarization: value);
  }

  Future<void> setSpeakerCount(int? count) async {
    if (count == null) {
      await _prefs.remove(_kSpeakerCount);
      state = state.copyWith(clearSpeakerCount: true);
    } else {
      await _prefs.setInt(_kSpeakerCount, count);
      state = state.copyWith(speakerCount: count);
    }
  }

  Future<void> setRequireLogin(bool value) async {
    await _prefs.setBool(_kRequireLogin, value);
    state = state.copyWith(requireLogin: value);
  }

  Future<void> setKeepScreenOn(bool value) async {
    await _prefs.setBool(_kKeepScreenOn, value);
    state = state.copyWith(keepScreenOn: value);
  }

  Future<void> setTranslationEnabled(bool value) async {
    await _prefs.setBool(_kTranslationEnabled, value);
    state = state.copyWith(translationEnabled: value);
  }

  /// 設定翻譯方向。
  ///
  /// 若新選的語言與對向相同(例如目標是英文,又把來源選成英文),就把對向換成
  /// 原本這一邊的語言 —— 等於自動交換,而不是拒絕選擇。這樣語言清單不需要
  /// 隱藏任何選項(先前隱藏對向語言,導致「中→英」時選不到英文當來源)。
  Future<void> setTranslationLanguages({String? source, String? target}) async {
    var src = source ?? state.translationSource;
    var tgt = target ?? state.translationTarget;
    if (src == tgt) {
      if (source != null) {
        tgt = state.translationSource; // 改來源撞到目標 → 目標接手舊來源
      } else {
        src = state.translationTarget; // 改目標撞到來源 → 來源接手舊目標
      }
    }
    if (src == tgt) return; // 極端情況(原本兩邊就相同)
    await _prefs.setString(_kTranslationSource, src);
    await _prefs.setString(_kTranslationTarget, tgt);
    state = state.copyWith(translationSource: src, translationTarget: tgt);
  }

  /// 一鍵反轉翻譯方向(中→英 變 英→中)。
  Future<void> swapTranslationLanguages() async {
    final src = state.translationTarget;
    final tgt = state.translationSource;
    await _prefs.setString(_kTranslationSource, src);
    await _prefs.setString(_kTranslationTarget, tgt);
    state = state.copyWith(translationSource: src, translationTarget: tgt);
  }
}
