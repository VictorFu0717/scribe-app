import 'dart:io';

import 'package:flutter/services.dart';

/// 把錄音的 WAV 轉成 m4a(AAC)。
///
/// 為什麼需要:錄音為 16kHz/mono/16-bit PCM,一小時的 WAV 約 **110MB** ——
/// 佔手機空間,而且大到無法用 LINE 等通訊軟體傳送(實測 15 秒可傳、一小時不行)。
/// 同樣內容轉成 AAC 約 **28MB**(64kbps),仍便於用通訊軟體傳送。
///
/// 用各平台原生編碼器(iOS AVFoundation / Android MediaCodec)而不引入
/// ffmpeg 之類的套件:體積小、無額外原生編譯風險(本專案已多次因 plugin 受阻)。
class AudioConvert {
  AudioConvert._();

  static const MethodChannel _channel = MethodChannel('app/audio_convert');

  /// AAC 位元率。
  ///
  /// 不用更低的值(例如系統自動選的 ~21kbps):本機檔案會用於「斷線後重新轉錄」,
  /// 而研究指出 16kbps 級別的壓縮會使 ASR 的 WER 相對劣化約 12.6%。
  /// 64kbps 對 16kHz 單聲道語音是 4:1 壓縮,一小時約 28MB 仍便於傳送,
  /// 且兩平台採同一設定以避免辨識品質不一致。
  static const int _bitRate = 64000;

  /// 將 [wavPath] 轉為同目錄的 `.m4a`,成功回傳新路徑,失敗回 null。
  ///
  /// [deleteSource] 為 true 時,轉檔成功後刪除原始 WAV(省空間)。
  /// 失敗時**不會**刪除原檔 —— 錄音檔是使用者的資料,不能因轉檔失敗而遺失。
  static Future<String?> wavToM4a(String wavPath,
      {bool deleteSource = true}) async {
    if (!File(wavPath).existsSync()) return null;
    final dst =
        '${wavPath.replaceAll(RegExp(r'\.wav$', caseSensitive: false), '')}.m4a';
    try {
      final ok = await _channel.invokeMethod<bool>('wavToM4a', {
            'src': wavPath,
            'dst': dst,
            'bitRate': _bitRate,
          }) ??
          false;
      if (!ok || !File(dst).existsSync()) return null;
      if (deleteSource) {
        try {
          await File(wavPath).delete();
        } catch (_) {}
      }
      return dst;
    } catch (_) {
      return null; // 平台未實作或編碼失敗:保留 WAV,呼叫端沿用原路徑
    }
  }
}
