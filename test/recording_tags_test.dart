import 'package:flutter_test/flutter_test.dart';
import 'package:meeting_assistant/models/meeting.dart';
import 'package:meeting_assistant/services/mock_backend.dart';

/// 錄音頁的標籤必須在**建立會議當下**就帶出去。
///
/// 若改成「先建立再 PATCH」,錄音一開始那段時間該會議是沒有標籤的;
/// server 也支援 POST 帶 tags,沒有理由多打一趟。
class _SpyBackend extends MockBackend {
  List<String>? tags;
  var calls = 0;

  @override
  Future<Meeting> createMeeting({required String title, List<String>? tags}) {
    calls++;
    this.tags = tags;
    return super.createMeeting(title: title, tags: tags);
  }
}

void main() {
  test('createMeeting 帶標籤時會正規化並存進會議', () async {
    final b = _SpyBackend();
    // 與 server 的 norm_tags 對齊:去空白、去重(不分大小寫)。
    final m = await b.createMeeting(
        title: '產品週會', tags: [' 專案會議 ', '專案會議', '每週會議']);
    expect(b.calls, 1);
    expect(m.tags, ['專案會議', '每週會議']);
  });

  test('沒選標籤時 tags 為空,不產生垃圾標籤', () async {
    final b = _SpyBackend();
    final m = await b.createMeeting(title: '產品週會', tags: const ['', '   ']);
    expect(m.tags, isEmpty);
  });

  test('單標籤超過 40 字會被截斷(與 server 上限一致)', () async {
    final b = _SpyBackend();
    final long = 'あ' * 60;
    final m = await b.createMeeting(title: 't', tags: [long]);
    expect(m.tags.single.length, 40);
  });

  test('最多 20 個標籤', () async {
    final b = _SpyBackend();
    final m = await b.createMeeting(
        title: 't', tags: [for (var i = 0; i < 30; i++) 'tag$i']);
    expect(m.tags, hasLength(20));
  });
}
