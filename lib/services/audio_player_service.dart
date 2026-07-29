import 'dart:io';

import 'package:just_audio/just_audio.dart';

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
  Future<bool> loadForMeeting({
    String? localPath,
    Uri? remoteUri,
    Map<String, String>? headers,
  }) async {
    if (localPath != null && await File(localPath).exists()) {
      await loadLocal(localPath);
      return true;
    }
    if (remoteUri != null) {
      await loadRemote(remoteUri, headers: headers);
      return true;
    }
    return false;
  }

  Future<void> play() => _player.play();
  Future<void> pause() => _player.pause();
  Future<void> seek(Duration position) => _player.seek(position);
  Future<void> stop() => _player.stop();

  Future<void> dispose() => _player.dispose();
}
