import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meeting_assistant/core/storage/token_storage.dart';
import 'package:meeting_assistant/models/transcription_config.dart';
import 'package:meeting_assistant/providers/upload_progress_controller.dart';
import 'package:meeting_assistant/services/http_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // 這個 binding 會攔截所有 HttpClient 並固定回 400。本測試的重點正是**真實**的
  // socket 寫入節奏(backpressure),不能被攔;拿掉覆寫改用真連線打本地 server。
  setUp(() => HttpOverrides.global = null);

  test('上傳進度必須反映真實的網路寫入,不能整檔緩衝後瞬間跳到 100%', () async {
    // 32MB 假音檔 —— 要遠大於 socket 緩衝(實測約 3MB),才分辨得出真假進度。
    final dir = await Directory.systemTemp.createTemp('upload_progress');
    final file = File('${dir.path}/a.wav');
    await file.writeAsBytes(Uint8List(32 * 1024 * 1024));

    // 慢慢讀 body 的 server,並記錄實際收到多少。
    //
    // 一定要直接 await for 這條 single-subscription stream —— 加 asBroadcastStream()
    // 會讓 backpressure 失效(廣播流不會因為訂閱者處理得慢而暫停來源),
    // server 就一點都不慢了。
    var received = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      await for (final chunk in req) {
        received += chunk.length;
        await Future<void>.delayed(const Duration(milliseconds: 15));
      }
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write('{"id":"m1","title":"t",'
            '"created_at":"2026-08-20T10:00:00Z","status":"transcribing"}');
      await req.response.close();
    });

    final backend = HttpBackend(
      baseUrl: 'http://127.0.0.1:${server.port}',
      tokenStorage: TokenStorage(),
    );

    // 每次回報都記下「當下 server 已收到多少」—— 這是真假進度的關鍵判準。
    final samples = <(int sent, int total, int received)>[];
    final sw = Stopwatch()..start();
    await backend.uploadAudio(
      'm1',
      file.path,
      config: const TranscriptionConfig(),
      onProgress: (sent, total) => samples.add((sent, total, received)),
    );
    sw.stop();

    expect(samples, isNotEmpty, reason: '完全沒有回報進度');

    // 單調遞增,且最後一筆剛好等於總量。
    for (var i = 1; i < samples.length; i++) {
      expect(samples[i].$1, greaterThanOrEqualTo(samples[i - 1].$1));
    }
    expect(samples.last.$1, samples.last.$2);
    expect(samples.last.$2, greaterThan(32 * 1024 * 1024));

    // **關鍵**:回報「已送出 N」時,server 應該真的已經收到接近 N 的量。
    // 若 package:http 把整條 stream 讀進記憶體才送,回報 100% 時 server 幾乎
    // 還沒收到東西 —— 那進度條是假的,而且 110MB 的錄音會爆記憶體。
    final last = samples.last;
    expect(last.$3 / last.$2, greaterThan(0.5),
        reason: '回報送出 100% 時 server 只收到 ${last.$3 >> 20}MB / '
            '${last.$2 >> 20}MB —— 這是緩衝後的假進度');

    // 落後量(socket 緩衝)全程都該有界,不該愈積愈多。
    for (final s in samples) {
      expect(s.$1 - s.$3, lessThan(12 * 1024 * 1024),
          reason: '送出量領先 server 太多,等於在記憶體裡累積整個檔案');
    }

    // 開頭不該就已經接近完成。
    final firstFraction = samples.first.$1 / samples.first.$2;
    expect(firstFraction, lessThan(0.5),
        reason: '第一次回報就已 ${(firstFraction * 100).round()}%,不是逐步上傳');

    backend.dispose();
    await server.close(force: true);
    await dir.delete(recursive: true);
  }, timeout: const Timeout(Duration(seconds: 120)));

  group('UploadProgressController 節流', () {
    test('百分比沒變就不更新 state —— 上傳一小時錄音會被呼叫上千次', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final c = container.read(uploadProgressProvider.notifier);
      c.begin();

      const total = 100 * 1024 * 1024;
      var updates = 0;
      // 直接數 state 物件變化(不經 Riverpod container,純邏輯測試)。
      UploadProgressState? prev;
      void tick(int sent) {
        c.onBytes(sent, total);
        if (!identical(prev, c.state)) {
          updates++;
          prev = c.state;
        }
      }

      // 模擬 64KB 一塊,共 1600 次回呼。
      const chunk = 64 * 1024;
      for (var sent = chunk; sent <= total; sent += chunk) {
        tick(sent);
      }

      expect(c.state.percent, 100);
      // 最多 101 種百分比 + 最後的 processing 轉換。
      expect(updates, lessThanOrEqualTo(102),
          reason: '沒節流的話 UI 每秒會重繪數十次(實際回呼 ${total ~/ chunk} 次)');
      expect(updates, greaterThan(50), reason: '節流過頭會讓進度條看起來不動');
    });

    test('位元組送完後轉為 processing —— 停在 100% 不動會被當成當掉', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final c = container.read(uploadProgressProvider.notifier);
      c.begin();
      c.onBytes(500, 1000);
      expect(c.state.phase, UploadPhase.uploading);
      expect(c.state.percent, 50);

      c.onBytes(1000, 1000);
      expect(c.state.phase, UploadPhase.processing,
          reason: 'server 還要存檔並建立轉錄工作,那段沒有進度可報');
    });

    test('總量未知時不假裝有百分比', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final c = container.read(uploadProgressProvider.notifier);
      c.begin();
      c.onBytes(123, 0);
      expect(c.state.percent, isNull);
      expect(c.state.fraction, isNull);
    });
  });
}
