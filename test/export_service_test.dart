import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:meeting_assistant/models/meeting.dart';
import 'package:meeting_assistant/models/summary.dart';
import 'package:meeting_assistant/models/transcript_segment.dart';
import 'package:meeting_assistant/services/export_service.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('zh_TW', null);
  });

  final meeting = Meeting(
    id: 'm1',
    title: '產品週會',
    createdAt: DateTime(2026, 7, 30, 14, 12),
  );

  test('buildTranscriptText:標題 + 說話者前綴,略過空片段', () {
    final txt = ExportService.buildTranscriptText(meeting, const [
      TranscriptSegment(id: 's0', text: '先確認里程碑。', isFinal: true, speaker: '說話者 1'),
      TranscriptSegment(id: 's1', text: '  ', isFinal: true, speaker: '說話者 2'),
      TranscriptSegment(id: 's2', text: '沒有說話者的一句。', isFinal: true),
    ]);
    expect(txt, contains('會議逐字稿'));
    expect(txt, contains('產品週會'));
    expect(txt, contains('說話者 1:先確認里程碑。'.replaceAll(':', '：')));
    expect(txt, contains('沒有說話者的一句。'));
    expect(txt, isNot(contains('說話者 2'))); // 空內容那句被略過
  });

  test('buildSummaryText:各區塊 + 待辦帶負責人/期限,空區塊省略', () {
    final txt = ExportService.buildSummaryText(
      meeting,
      const MeetingSummary(
        overview: '確認架構方向。',
        keyPoints: ['重點一', '重點二'],
        decisions: [],
        actionItems: [
          ActionItem(task: '建立 API 契約', owner: '小林', due: '本週五'),
          ActionItem(task: '無負責人的待辦'),
        ],
        followUps: ['下週追蹤'],
      ),
    );
    expect(txt, contains('【會議摘要】'));
    expect(txt, contains('確認架構方向。'));
    expect(txt, contains('【討論重點】'));
    expect(txt, contains('- 重點一'));
    expect(txt, contains('【待辦事項】'));
    expect(txt, contains('- 建立 API 契約(負責人:小林、期限:本週五)'));
    expect(txt, contains('- 無負責人的待辦'));
    expect(txt, contains('【後續追蹤】'));
    expect(txt, isNot(contains('【決議事項】'))); // 空 → 省略
  });
}
