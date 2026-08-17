import 'package:flutter_test/flutter_test.dart';
import 'package:meeting_assistant/providers/recording_controller.dart';
import 'package:meeting_assistant/services/backend.dart';

void main() {
  group('RecordingState.copyWith', () {
    test('更新其他欄位不得清掉 droppedAt —— 錄音中每秒都會 copyWith(elapsed:)', () {
      final t = DateTime(2026, 8, 18, 10);
      var s = const RecordingState().copyWith(
        linkState: TranscriptionLinkState.reconnecting,
        droppedAt: t,
      );
      expect(s.droppedAt, t);

      // 模擬錄音計時器:先前的寫法會在這裡把 droppedAt 清成 null,
      // 導致中斷警示紅字只閃一秒就消失。
      for (var i = 1; i <= 3; i++) {
        s = s.copyWith(elapsed: Duration(seconds: i));
      }
      expect(s.droppedAt, t, reason: '警示要能持續顯示,不能被無關的更新清掉');
      expect(s.linkState, TranscriptionLinkState.reconnecting);

      // 也不該被逐字稿更新清掉。
      s = s.copyWith(level: 0.5, translationStatus: TranslationStatus.off);
      expect(s.droppedAt, t);
    });

    test('連線恢復時以 clearDroppedAt 顯式清除', () {
      var s = const RecordingState().copyWith(droppedAt: DateTime(2026, 8, 18));
      s = s.copyWith(
        linkState: TranscriptionLinkState.online,
        clearDroppedAt: true,
      );
      expect(s.droppedAt, isNull);
    });
  });
}
