import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'save_to_device.dart';

/// 存圖的結果。[message] 是可直接顯示給使用者的中文;使用者自行取消時為 null。
class ImageSaveResult {
  const ImageSaveResult.ok(this.message) : ok = true;
  const ImageSaveResult.failed(this.message) : ok = false;

  final bool ok;
  final String? message;
}

/// 把圖片存進手機的相簿。
///
/// - iOS:存進「照片」。只要求「僅加入照片」權限,不讀取使用者的相簿
///   (需 Info.plist 的 NSPhotoLibraryAddUsageDescription)。
/// - Android 10 以上:寫進 MediaStore 的 Pictures/會議助理,相簿 App 直接看得到,
///   不需要任何權限。
/// - Android 9 以下:寫進公用相簿需要儲存權限,改走系統「另存新檔」對話框。
class ImageSaver {
  ImageSaver._();

  static const MethodChannel _channel = MethodChannel('app/save_image');

  /// 暫存目錄。測試時換掉(單元測試裡沒有 path_provider 的原生端)。
  @visibleForTesting
  static Future<Directory> Function() tempDir = getTemporaryDirectory;

  static Future<ImageSaveResult> saveJpeg(
    Uint8List bytes, {
    required String fileName,
  }) async {
    final dir = await tempDir();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    try {
      final platform = defaultTargetPlatform;
      if (platform == TargetPlatform.iOS) {
        final r = await _channel
            .invokeMethod<String>('saveToPhotos', {'path': file.path});
        return _interpret(r, savedTo: '已存到「照片」');
      }
      if (platform == TargetPlatform.android) {
        final r = await _channel.invokeMethod<String>(
            'saveToGallery', {'path': file.path, 'name': fileName});
        if (r == 'legacy') {
          final ok = await SaveToDevice.save(file.path,
              fileName: fileName, mimeType: 'image/jpeg');
          // 對話框被取消時不顯示任何訊息(那是使用者自己的選擇)
          return ok
              ? const ImageSaveResult.ok('已存檔')
              : const ImageSaveResult.failed(null);
        }
        return _interpret(r, savedTo: '已存到相簿(Pictures/會議助理)');
      }
      return const ImageSaveResult.failed('這個裝置不支援存圖');
    } on PlatformException catch (e) {
      return ImageSaveResult.failed('存圖失敗:${e.message ?? e.code}');
    } on MissingPluginException {
      return const ImageSaveResult.failed('存圖功能尚未就緒,請重新啟動 App');
    } finally {
      // 原生端回傳時已經複製進相簿,暫存檔可以刪
      try {
        await file.delete();
      } catch (_) {}
    }
  }

  /// 原生端回傳 "ok" / "denied" / "error: …"。
  static ImageSaveResult _interpret(String? r, {required String savedTo}) {
    if (r == 'ok') return ImageSaveResult.ok(savedTo);
    if (r == 'denied') {
      return ImageSaveResult.failed(defaultTargetPlatform == TargetPlatform.iOS
          ? '沒有加入照片的權限。請到「設定 > 隱私權與安全性 > 照片 > 會議助理」允許「僅加入照片」。'
          : '沒有存到相簿的權限。');
    }
    final detail = (r ?? '').replaceFirst(RegExp(r'^error:\s*'), '');
    return ImageSaveResult.failed(detail.isEmpty ? '存圖失敗' : '存圖失敗:$detail');
  }
}
