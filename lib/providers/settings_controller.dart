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

  Settings copyWith({
    String? baseUrl,
    bool? useMock,
    bool? diarization,
    int? speakerCount,
    bool clearSpeakerCount = false,
    bool? requireLogin,
    bool? keepScreenOn,
  }) {
    return Settings(
      baseUrl: baseUrl ?? this.baseUrl,
      useMock: useMock ?? this.useMock,
      diarization: diarization ?? this.diarization,
      speakerCount:
          clearSpeakerCount ? null : (speakerCount ?? this.speakerCount),
      requireLogin: requireLogin ?? this.requireLogin,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
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
}
