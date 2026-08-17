import 'package:flutter_test/flutter_test.dart';
import 'package:meeting_assistant/services/http_backend.dart';

void main() {
  group('WS 重連退避', () {
    test('前幾次快速重試,對付 VPN 短暫抖動', () {
      expect(wsRetryDelaySeconds(1), 1);
      expect(wsRetryDelaySeconds(2), 2);
      expect(wsRetryDelaySeconds(3), 3);
    });

    test('之後拉長但穩定在 15 秒,不會無限增長到永遠等不到', () {
      expect(wsRetryDelaySeconds(4), 5);
      expect(wsRetryDelaySeconds(6), 5);
      expect(wsRetryDelaySeconds(7), 15);
      expect(wsRetryDelaySeconds(100), 15);
    });

    test('錄音期間永不放棄:再多次數都仍回傳可用的等待秒數', () {
      // 一小時斷線約 240 次重試;先前 12 次就放棄,恢復也連不回來。
      for (final attempt in [12, 13, 240, 10000]) {
        final secs = wsRetryDelaySeconds(attempt);
        expect(secs, greaterThan(0), reason: 'attempt $attempt 應仍會重試');
        expect(secs, lessThanOrEqualTo(15), reason: 'attempt $attempt 間隔不該過長');
      }
    });
  });
}
