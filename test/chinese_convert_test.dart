import 'package:flutter_test/flutter_test.dart';
import 'package:meeting_assistant/services/chinese_convert.dart';

/// 驗證簡→繁(台灣)轉換:ML Kit 的中文譯文只有簡體,必須靠這層轉成繁體。
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await ChineseConvert.ensureLoaded();
  });

  test('字典載入成功', () {
    expect(ChineseConvert.isReady, isTrue);
  });

  test('基本字元轉換', () {
    expect(ChineseConvert.s2twp('简体中文'), '簡體中文');
    expect(ChineseConvert.s2twp('会议记录'), '會議記錄');
  });

  test('歧義字需靠詞組(字元級會轉錯)', () {
    // 「发」可對應 發/髮 —— 靠詞組才會正確。
    expect(ChineseConvert.s2twp('头发'), '頭髮');
    expect(ChineseConvert.s2twp('发展'), '發展');
    // 「干」可對應 幹/乾/干。
    expect(ChineseConvert.s2twp('干净'), '乾淨');
  });

  test('台灣用語轉換', () {
    expect(ChineseConvert.s2twp('软件'), '軟體');
    expect(ChineseConvert.s2twp('网络'), '網路');
    expect(ChineseConvert.s2twp('信息'), '資訊');
    expect(ChineseConvert.s2twp('视频'), '影片');
  });

  test('混合內容與非中文原樣保留', () {
    expect(ChineseConvert.s2twp('这个 API 用于处理数据'), '這個 API 用於處理資料');
    expect(ChineseConvert.s2twp('Hello, world!'), 'Hello, world!');
    expect(ChineseConvert.s2twp(''), '');
  });

  test('已是繁體則不應被破壞', () {
    expect(ChineseConvert.s2twp('會議記錄'), '會議記錄');
  });
}
