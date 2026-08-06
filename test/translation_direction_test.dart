import 'package:flutter_test/flutter_test.dart';
import 'package:meeting_assistant/services/on_device_translator.dart';

/// 翻譯方向的自動修正。
///
/// 實測到的問題:翻譯方向是全域設定,但每場會議語言不同。把設定改成「中文→英文」
/// 後再開啟一場**英文**會議,會用 zh→en 去翻英文逐字稿,ML Kit 原樣吐回 →
/// 畫面呈現「英文翻英文」。反之中文會議套上 en→zh 則譯文變中文。
void main() {
  group('looksChinese', () {
    test('中文為主', () {
      expect(looksChinese('今天的會議討論了三個議題'), isTrue);
      expect(looksChinese('這個 API 的設計需要調整'), isTrue); // 夾雜英文仍以中文為主
    });

    test('英文為主', () {
      expect(looksChinese('We need to review the API design today'), isFalse);
      expect(looksChinese('OK, 我 們'), isFalse); // 拉丁字母較多
    });
  });

  group('resolveDirection', () {
    test('語言相符時維持使用者設定', () {
      final d = resolveDirection(
          sampleText: '今天的會議討論了三個議題', source: 'zh', target: 'en');
      expect(d.source, 'zh');
      expect(d.target, 'en');
    });

    test('英文逐字稿卻設成 zh→en:自動反轉,避免「英文翻英文」', () {
      final d = resolveDirection(
          sampleText: 'We need to review the API design today',
          source: 'zh',
          target: 'en');
      expect(d.source, 'en');
      expect(d.target, 'zh');
    });

    test('中文逐字稿卻設成 en→zh:自動反轉,避免譯文變中文', () {
      final d = resolveDirection(
          sampleText: '今天的會議討論了三個議題', source: 'en', target: 'zh');
      expect(d.source, 'zh');
      expect(d.target, 'en');
    });

    test('雙方都非中文時無從判斷,維持設定', () {
      final d = resolveDirection(
          sampleText: 'We need to review this', source: 'en', target: 'ja');
      expect(d.source, 'en');
      expect(d.target, 'ja');
    });

    test('空白內容維持設定', () {
      final d = resolveDirection(sampleText: '   ', source: 'zh', target: 'en');
      expect(d.source, 'zh');
      expect(d.target, 'en');
    });
  });
}
