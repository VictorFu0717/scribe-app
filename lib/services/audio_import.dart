import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/meetings_controller.dart';
import '../providers/service_providers.dart';

/// 匯入一個既有音檔:建立會議 → 上傳給 server 背景轉錄 → 回傳 meetingId。
///
/// 由兩處共用:會議清單的「上傳音檔」按鈕,以及從其他 App 分享進來的音檔
/// (見 [IncomingFile])。失敗時丟出例外,由呼叫端顯示訊息。
///
/// 取 WidgetRef 而非 Ref:兩個呼叫端都在 widget 內(清單頁與 HomeShell)。
Future<String> importAudioFile(WidgetRef ref, String path) async {
  final backend = ref.read(backendProvider);
  final config = ref.read(transcriptionConfigProvider);

  final meeting = await backend.createMeeting(title: titleFromPath(path));
  await backend.uploadAudio(meeting.id, path, config: config);
  ref.invalidate(meetingsListProvider);
  return meeting.id;
}

/// 以檔名(去副檔名)當會議標題;取不到時給預設值。
String titleFromPath(String path) {
  final name = path.split(Platform.pathSeparator).last;
  final dot = name.lastIndexOf('.');
  final base = (dot > 0 ? name.substring(0, dot) : name).trim();
  return base.isEmpty ? '匯入的錄音' : base;
}
