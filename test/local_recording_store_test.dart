import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meeting_assistant/providers/service_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 模擬 iOS 的沙盒:/…/Application/<UUID>/Documents。每次安裝/更新 App,
/// UUID 都會換,檔案被搬到新資料夾,舊路徑就不存在了。
void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('container'));
  tearDown(() => root.deleteSync(recursive: true));

  String docsFor(String uuid) {
    final d = Directory('${root.path}/Application/$uuid/Documents')
      ..createSync(recursive: true);
    return d.path;
  }

  File put(String docs, String name, {int bytes = 1024}) =>
      File('$docs/$name')..writeAsBytesSync(List.filled(bytes, 7));

  Future<SharedPreferences> prefsWith(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    return SharedPreferences.getInstance();
  }

  test('更新 App 後(沙盒 UUID 換了),舊版存的絕對路徑仍找得回錄音檔', () async {
    // 舊版在 AAAA 資料夾裡錄的,記下了絕對路徑
    final oldPath = '${root.path}/Application/AAAA/Documents/rec_58270311abe5.wav';
    // 更新後檔案被搬到 BBBB,舊資料夾已不存在
    final newDocs = docsFor('BBBB');
    final moved = put(newDocs, 'rec_58270311abe5.wav');

    final prefs = await prefsWith({'local_audio.m1': oldPath});
    final store = LocalRecordingStore(prefs, documentsDir: newDocs);

    expect(store.pathFor('m1'), moved.path,
        reason: '這正是使用者回報的:每次更新後錄音都「不見」,其實檔案都還在');
  });

  test('找回之後改存成檔名,下一次更新也不會再丟', () async {
    final oldPath = '${root.path}/Application/AAAA/Documents/rec_x.wav';
    final docs1 = docsFor('BBBB');
    put(docs1, 'rec_x.wav');
    final prefs = await prefsWith({'local_audio.m1': oldPath});

    LocalRecordingStore(prefs, documentsDir: docs1).pathFor('m1');
    expect(prefs.getString('local_audio.m1'), 'rec_x.wav',
        reason: '自我修復:不再依賴會變的絕對路徑');

    // 再更新一次:又換了資料夾
    final docs2 = docsFor('CCCC');
    final again = put(docs2, 'rec_x.wav');
    expect(LocalRecordingStore(prefs, documentsDir: docs2).pathFor('m1'),
        again.path);
  });

  test('新存的錄音只記檔名', () async {
    final docs = docsFor('BBBB');
    final f = put(docs, 'rec_new.wav');
    final prefs = await prefsWith({});
    final store = LocalRecordingStore(prefs, documentsDir: docs);

    await store.save('m1', f.path);
    expect(prefs.getString('local_audio.m1'), 'rec_new.wav');
    expect(store.pathFor('m1'), f.path);
  });

  test('早期壓縮失敗留下 0 位元組的 .m4a 時,改用同名的 .wav', () async {
    final docs = docsFor('BBBB');
    put(docs, 'rec_c47610bc9014.m4a', bytes: 0);
    final wav = put(docs, 'rec_c47610bc9014.wav');
    final prefs = await prefsWith({'local_audio.m1': 'rec_c47610bc9014.m4a'});

    expect(LocalRecordingStore(prefs, documentsDir: docs).pathFor('m1'),
        wav.path,
        reason: '指向空檔的話,播放器會出現卻放不出聲音');
  });

  test('仍然有效的絕對路徑直接用(Android 的路徑不會隨更新改變)', () async {
    final docs = docsFor('BBBB');
    final elsewhere = Directory('${root.path}/elsewhere')..createSync();
    final f = put(elsewhere.path, 'a.wav');
    final prefs = await prefsWith({'local_audio.m1': f.path});

    expect(LocalRecordingStore(prefs, documentsDir: docs).pathFor('m1'), f.path);
  });

  test('真的找不到就回傳原值(交由畫面判斷不顯示播放器),不亂猜', () async {
    final docs = docsFor('BBBB');
    final gone = '${root.path}/Application/AAAA/Documents/rec_gone.wav';
    final prefs = await prefsWith({'local_audio.m1': gone});

    final p = LocalRecordingStore(prefs, documentsDir: docs).pathFor('m1');
    expect(p, gone);
    expect(File(p!).existsSync(), isFalse);
    expect(prefs.getString('local_audio.m1'), gone, reason: '沒找到就不改記錄');
  });

  test('取不到 Documents 時維持舊行為', () async {
    final prefs = await prefsWith({'local_audio.m1': '/some/abs/path.wav'});
    expect(LocalRecordingStore(prefs).pathFor('m1'), '/some/abs/path.wav');
  });

  test('沒有記錄、也沒有對應檔案就回 null', () async {
    final prefs = await prefsWith({});
    expect(LocalRecordingStore(prefs, documentsDir: docsFor('B')).pathFor('m1'),
        isNull);
  });

  test('檔案在、記錄不在時,照命名規則找回並補寫記錄', () async {
    // 早期上傳大檔途中閃退,記錄來不及寫入(實測手機裡有 6 個)
    final docs = docsFor('BBBB');
    final rec = put(docs, 'rec_d955aa68adae.wav');
    final imp = put(docs, 'import_0c001b975c37.mp3');
    put(docs, 'import_1e296e18fc02.m4a', bytes: 0); // 空檔不算
    final wav = put(docs, 'import_1e296e18fc02.wav');
    final prefs = await prefsWith({});
    final store = LocalRecordingStore(prefs, documentsDir: docs);

    expect(store.pathFor('d955aa68adae'), rec.path);
    expect(store.pathFor('0c001b975c37'), imp.path);
    expect(store.pathFor('1e296e18fc02'), wav.path);
    expect(prefs.getString('local_audio.d955aa68adae'), 'rec_d955aa68adae.wav');
  });

  test('命名規則只認完整的會議 id,不會撿到別場的檔案', () async {
    final docs = docsFor('BBBB');
    put(docs, 'rec_abc123.wav');
    final prefs = await prefsWith({});
    final store = LocalRecordingStore(prefs, documentsDir: docs);
    expect(store.pathFor('abc'), isNull);
    expect(store.pathFor('abc1234'), isNull);
  });
}
