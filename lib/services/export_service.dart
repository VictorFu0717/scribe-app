import 'dart:io';
import 'dart:ui';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/utils/formatters.dart';
import '../models/meeting.dart';
import '../models/summary.dart';
import '../models/transcript_segment.dart';

/// 把逐字稿 / 摘要輸出成 .txt,並叫出系統分享/儲存面板
/// (iOS「儲存到檔案」、Android 存到下載/雲端等)。
class ExportService {
  ExportService._();

  /// 匯出逐字稿。若該場會議開了翻譯,譯文會一併寫入(每句原文下方縮排一行)。
  static Future<void> exportTranscript(
    Meeting meeting,
    List<TranscriptSegment> segments, {
    Rect? shareOrigin,
    Map<String, String> translations = const {},
    String? translationNote,
  }) {
    final name = '${_sanitize(meeting.title)}_逐字稿_${_stamp(meeting.createdAt)}';
    return _saveAndShare(
      name,
      buildTranscriptText(meeting, segments,
          translations: translations, translationNote: translationNote),
      shareOrigin,
    );
  }

  static Future<void> exportSummary(
    Meeting meeting,
    MeetingSummary summary, {
    Rect? shareOrigin,
  }) {
    final name = '${_sanitize(meeting.title)}_摘要_${_stamp(meeting.createdAt)}';
    return _saveAndShare(name, buildSummaryText(meeting, summary), shareOrigin);
  }

  /// 分享本地錄音檔(iOS「儲存到檔案」、AirDrop、其他 App…)。
  /// 直接分享沙盒內的原檔,只把顯示檔名換成好認的名稱,不額外複製大檔。
  static Future<void> exportAudio(
    Meeting meeting,
    String audioPath, {
    Rect? shareOrigin,
  }) async {
    if (!await File(audioPath).exists()) {
      throw StateError('找不到本地錄音檔(可能已被清除)');
    }
    final ext = _ext(audioPath);
    final name = audioFileName(meeting, audioPath);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(audioPath, mimeType: _audioMime(ext), name: name)],
      subject: name,
      sharePositionOrigin: shareOrigin,
    ));
  }

  // ── 內容組裝 ──
  /// 組出逐字稿純文字。
  ///
  /// [translations] 為片段 id → 譯文;有值時寫在該句原文下一行並縮排,
  /// 讓匯出的內容與 App 內看到的雙語一致。[translationNote] 標示翻譯方向。
  static String buildTranscriptText(
    Meeting m,
    List<TranscriptSegment> segs, {
    Map<String, String> translations = const {},
    String? translationNote,
  }) {
    final b = StringBuffer()
      ..writeln('會議逐字稿')
      ..writeln(m.title)
      ..writeln(Formatters.dateTime(m.createdAt));
    if (translationNote != null && translationNote.isNotEmpty) {
      b.writeln('翻譯:$translationNote');
    }
    b.writeln();
    for (final s in segs) {
      final t = s.text.trim();
      if (t.isEmpty) continue;
      b.writeln(s.speaker != null ? '${s.speaker}：$t' : t);
      final translated = translations[s.id]?.trim();
      if (translated != null && translated.isNotEmpty) {
        b.writeln('    $translated');
      }
    }
    return b.toString();
  }

  static String buildSummaryText(Meeting m, MeetingSummary s) {
    final b = StringBuffer()
      ..writeln('會議摘要記錄')
      ..writeln(m.title)
      ..writeln(Formatters.dateTime(m.createdAt))
      ..writeln();

    void bulletSection(String title, List<String> lines) {
      if (lines.isEmpty) return;
      b.writeln('【$title】');
      for (final l in lines) {
        b.writeln('- $l');
      }
      b.writeln();
    }

    if (s.overview.isNotEmpty) {
      b
        ..writeln('【會議摘要】')
        ..writeln(s.overview)
        ..writeln();
    }
    bulletSection('討論重點', s.keyPoints);
    bulletSection('決議事項', s.decisions);
    if (s.actionItems.isNotEmpty) {
      b.writeln('【待辦事項】');
      for (final a in s.actionItems) {
        final meta = [
          if (a.owner != null) '負責人:${a.owner}',
          if (a.due != null) '期限:${a.due}',
        ].join('、');
        b.writeln(meta.isEmpty ? '- ${a.task}' : '- ${a.task}($meta)');
      }
      b.writeln();
    }
    bulletSection('後續追蹤', s.followUps);
    return b.toString();
  }

  // ── 寫檔 + 分享 ──
  static Future<void> _saveAndShare(
      String baseName, String text, Rect? origin) async {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/$baseName.txt';
    await File(path).writeAsString(text);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(path, mimeType: 'text/plain', name: '$baseName.txt')],
      subject: baseName,
      sharePositionOrigin: origin, // iPad 需要錨點
    ));
  }

  /// 錄音檔對外顯示的檔名(分享與「存到手機」共用,兩處要一致)。
  static String audioFileName(Meeting meeting, String audioPath) =>
      '${_sanitize(meeting.title)}_錄音_${_stamp(meeting.createdAt)}'
      '.${_ext(audioPath)}';

  /// 錄音檔的 MIME type(供「存到手機」建立文件時使用)。
  static String audioMimeType(String audioPath) => _audioMime(_ext(audioPath));

  static String _ext(String path) {
    final i = path.lastIndexOf('.');
    return i >= 0 ? path.substring(i + 1).toLowerCase() : 'wav';
  }

  static String _audioMime(String ext) {
    switch (ext) {
      case 'wav':
        return 'audio/wav';
      case 'm4a':
        return 'audio/mp4';
      case 'mp3':
        return 'audio/mpeg';
      case 'aac':
        return 'audio/aac';
      case 'aiff':
        return 'audio/aiff';
      case 'caf':
        return 'audio/x-caf';
      case 'flac':
        return 'audio/flac';
      default:
        return 'application/octet-stream';
    }
  }

  static String _sanitize(String s) {
    final cleaned =
        s.replaceAll(RegExp(r'[\/\\:*?"<>|\n\r\t]'), '_').trim();
    return cleaned.isEmpty ? '會議' : cleaned;
  }

  static String _stamp(DateTime dt) {
    final d = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}${two(d.month)}${two(d.day)}';
  }
}
