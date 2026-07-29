import 'package:flutter_test/flutter_test.dart';
import 'package:meeting_assistant/core/utils/think_parser.dart';
import 'package:meeting_assistant/models/summary.dart';

void main() {
  group('ThinkParser', () {
    test('分離單一 <think> 區塊', () {
      final p = ThinkParser()..add('<think>推理內容</think>答案');
      p.flush();
      expect(p.thinking, '推理內容');
      expect(p.visible, '答案');
    });

    test('無 think 時全部為可見', () {
      final p = ThinkParser()..add('只有答案');
      p.flush();
      expect(p.visible, '只有答案');
      expect(p.hasThinking, isFalse);
    });

    test('標籤跨 chunk 切斷仍能正確分離', () {
      final p = ThinkParser();
      // 模擬串流:標籤被切在多個 chunk
      for (final c in ['<thi', 'nk>推理', '過程</thi', 'nk>最終', '答案']) {
        p.add(c);
      }
      p.flush();
      expect(p.thinking, '推理過程');
      expect(p.visible, '最終答案');
    });

    test('逐字元串流答案不遺漏', () {
      final p = ThinkParser();
      const full = '<think>t</think>Hello 世界';
      for (final ch in full.split('')) {
        p.add(ch);
      }
      p.flush();
      expect(p.visible, 'Hello 世界');
    });
  });

  group('MeetingSummary.fromJson', () {
    test('解析 snake_case 與 action items', () {
      final s = MeetingSummary.fromJson({
        'overview': '概述',
        'key_points': ['一', '二'],
        'decisions': ['決議'],
        'action_items': [
          {'task': '待辦', 'owner': '小林', 'due': '週五'}
        ],
        'follow_ups': ['追蹤'],
      });
      expect(s.overview, '概述');
      expect(s.keyPoints.length, 2);
      expect(s.actionItems.single.owner, '小林');
      expect(s.followUps.single, '追蹤');
    });
  });
}
