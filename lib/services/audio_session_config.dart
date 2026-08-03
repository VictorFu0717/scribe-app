import 'package:audio_session/audio_session.dart';

/// 錄音與播放需要不同的 audio session 設定,否則會互相干擾:
/// - 錄音:`playAndRecord`(要用麥克風)。
/// - 播放:`playback` / Android `media` usage → 走**擴音**(loudspeaker),
///   而非通話用的聽筒(earpiece)。
///
/// 單一 `playAndRecord`+`voiceCommunication` 會讓播放走聽筒,所以在錄音/播放
/// 切換時各自套用對應設定。
class AudioSessions {
  AudioSessions._();

  /// 播放用:媒體輸出 → 擴音。app 啟動與每次播放前套用。
  static Future<void> playback() async {
    try {
      final s = await AudioSession.instance;
      await s.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionMode: AVAudioSessionMode.spokenAudio,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          usage: AndroidAudioUsage.media, // media → 擴音
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      ));
    } catch (_) {}
  }

  /// 錄音用:playAndRecord(需麥克風);iOS 加 defaultToSpeaker。
  static Future<void> recording() async {
    try {
      final s = await AudioSession.instance;
      await s.configure(AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.allowBluetooth |
                AVAudioSessionCategoryOptions.defaultToSpeaker,
        avAudioSessionMode: AVAudioSessionMode.spokenAudio,
        androidAudioAttributes: const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          usage: AndroidAudioUsage.voiceCommunication,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      ));
    } catch (_) {}
  }
}
