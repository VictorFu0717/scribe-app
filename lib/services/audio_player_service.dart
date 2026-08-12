import 'dart:io';

import 'package:just_audio/just_audio.dart';

import 'audio_session_config.dart';

/// 播放服務:本地錄音檔或 server 遠端音檔。
class AudioPlayerService {
  final AudioPlayer _player = AudioPlayer();

  AudioPlayer get player => _player;

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  Future<void> loadLocal(String path) async {
    await _player.setFilePath(path);
  }

  Future<void> loadRemote(Uri uri, {Map<String, String>? headers}) async {
    await _player.setAudioSource(
      AudioSource.uri(uri, headers: headers),
    );
  }

  /// 依會議提供的本地/遠端來源自動載入(本地優先)。
  /// 目前載入的音源屬於哪一場會議。
  ///
  /// 播放器是 App 層級共用的 singleton —— 切換到「沒有音檔」的會議時,裡面還留著
  /// 上一場的音源。若不檢查就 seek/play,會播出**別場**會議的錄音(實測發生過)。
  String? _loadedMeetingId;
  String? get loadedMeetingId => _loadedMeetingId;

  Future<bool> loadForMeeting({
    String? meetingId,
    String? localPath,
    Uri? remoteUri,
    Map<String, String>? headers,
  }) async {
    // 播放前套用播放設定(走擴音,而非錄音時的聽筒路由)。
    await AudioSessions.playback();
    if (localPath != null && await File(localPath).exists()) {
      await loadLocal(localPath);
      _loadedMeetingId = meetingId;
      return true;
    }
    if (remoteUri != null) {
      await loadRemote(remoteUri, headers: headers);
      _loadedMeetingId = meetingId;
      return true;
    }
    _loadedMeetingId = null;
    return false;
  }

  Future<void> play() => _player.play();
  Future<void> pause() => _player.pause();
  Future<void> seek(Duration position) => _player.seek(position);
  Future<void> stop() {
    _loadedMeetingId = null; // 停掉就不再屬於任何會議,避免之後誤 seek
    return _player.stop();
  }

  Future<void> dispose() => _player.dispose();
}
