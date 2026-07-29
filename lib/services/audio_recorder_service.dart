import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../core/config/app_config.dart';

/// 錄音服務:以 `record` 取得 16kHz/mono/16-bit PCM 串流(供 WS 即時上傳),
/// 同時把原始 PCM 落地成本地檔,停止時封裝為 WAV(供播放與斷線後補上傳)。
///
/// 背景/鎖屏錄音:iOS 於 Info.plist 開啟 `audio` background mode;
/// Android 需 RECORD_AUDIO + FOREGROUND_SERVICE_MICROPHONE(見 AndroidManifest)。
class AudioRecorderService {
  final AudioRecorder _recorder = AudioRecorder();

  IOSink? _pcmSink;
  String? _pcmPath;
  int _pcmBytes = 0;

  Future<bool> hasPermission() => _recorder.hasPermission();

  Future<bool> get isRecording => _recorder.isRecording();

  /// 開始錄音,回傳 PCM 音框串流(每框為 16-bit LE mono）。
  Future<Stream<Uint8List>> start({required String meetingId}) async {
    if (!await _recorder.hasPermission()) {
      throw StateError('沒有麥克風權限');
    }
    final dir = await getApplicationDocumentsDirectory();
    _pcmPath = '${dir.path}/rec_$meetingId.pcm';
    _pcmSink = File(_pcmPath!).openWrite();
    _pcmBytes = 0;

    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: AppConfig.sampleRate,
        numChannels: AppConfig.numChannels,
      ),
    );

    // 邊串流邊落地本地檔(防斷線)。
    return stream.map((chunk) {
      _pcmSink?.add(chunk);
      _pcmBytes += chunk.length;
      return chunk;
    });
  }

  Future<void> pause() => _recorder.pause();
  Future<void> resume() => _recorder.resume();

  /// 停止錄音,回傳可播放的 WAV 檔路徑(失敗回 null)。
  Future<String?> stop() async {
    await _recorder.stop();
    await _pcmSink?.flush();
    await _pcmSink?.close();
    _pcmSink = null;

    final pcmPath = _pcmPath;
    if (pcmPath == null || _pcmBytes == 0) return null;
    final wavPath = pcmPath.replaceAll('.pcm', '.wav');
    await _wrapPcmAsWav(pcmPath, wavPath, _pcmBytes);
    // 清掉原始 PCM 檔,只留 WAV。
    try {
      await File(pcmPath).delete();
    } catch (_) {}
    _pcmPath = null;
    return wavPath;
  }

  Future<void> dispose() => _recorder.dispose();

  /// 把原始 PCM 檔封裝成 WAV(串流複製,避免大檔佔記憶體)。
  static Future<void> _wrapPcmAsWav(
      String pcmPath, String wavPath, int dataLen) async {
    const sampleRate = AppConfig.sampleRate;
    const channels = AppConfig.numChannels;
    const bitsPerSample = 16;
    final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    final blockAlign = channels * bitsPerSample ~/ 8;

    final header = BytesBuilder();
    void writeStr(String s) => header.add(s.codeUnits);
    void writeU32(int v) => header.add(Uint8List(4)
      ..buffer.asByteData().setUint32(0, v, Endian.little));
    void writeU16(int v) => header.add(Uint8List(2)
      ..buffer.asByteData().setUint16(0, v, Endian.little));

    writeStr('RIFF');
    writeU32(36 + dataLen);
    writeStr('WAVE');
    writeStr('fmt ');
    writeU32(16); // PCM fmt chunk size
    writeU16(1); // audio format = PCM
    writeU16(channels);
    writeU32(sampleRate);
    writeU32(byteRate);
    writeU16(blockAlign);
    writeU16(bitsPerSample);
    writeStr('data');
    writeU32(dataLen);

    final out = File(wavPath).openWrite();
    out.add(header.toBytes());
    await out.addStream(File(pcmPath).openRead());
    await out.flush();
    await out.close();
  }
}
