import 'dart:io';

import 'package:flutter/services.dart';

/// 把錄音的 WAV 轉成 m4a(AAC)。
///
/// 為什麼需要:錄音為 16kHz/mono/16-bit PCM,一小時的 WAV 約 **110MB** ——
/// 佔手機空間,而且大到無法用 LINE 等通訊軟體傳送(實測 15 秒可傳、一小時不行)。
/// 同樣內容轉成 AAC 只需約 **9MB**(實測壓縮約 12 倍),音質對語音而言足夠。
///
/// 用各平台原生編碼器(iOS AVFoundation / Android MediaCodec)而不引入
/// ffmpeg 之類的套件:體積小、無額外原生編譯風險(本專案已多次因 plugin 受阻)。
class AudioConvert {
  AudioConvert._();

  static const MethodChannel _channel = MethodChannel('app/audio_convert');

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
