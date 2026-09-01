import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meeting_assistant/core/theme/app_theme.dart';
import 'package:meeting_assistant/models/meeting.dart';
import 'package:meeting_assistant/providers/service_providers.dart';
import 'package:meeting_assistant/providers/settings_controller.dart';
import 'package:meeting_assistant/services/backend.dart';
import 'package:meeting_assistant/services/mock_backend.dart';
import 'package:meeting_assistant/widgets/meeting_tags_row.dart';
import 'package:meeting_assistant/widgets/tag_editor_row.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 在 fake async 之外跑 setup。
///
/// **必須這樣做**:testWidgets 的 body 跑在 FakeAsync 裡,時間只在 pump 時前進。
/// MockBackend 每個方法都有 Future.delayed,在 pumpWidget 之前直接 await 會永久
/// 卡住(實測整個 flutter test 沒有任何輸出就停住)。runAsync 用真實時鐘。
Future<T> _real<T>(WidgetTester tester, Future<T> Function() action) async {
  final r = await tester.runAsync(action);
  return r as T;
}

/// 推進畫面。
///
/// **不能用 pumpAndSettle**:載入中會顯示 CircularProgressIndicator,那是無限
/// 動畫,永遠有下一帧要排程 —— pumpAndSettle 會一直等到逾時。
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

/// 記錄 updateMeeting 收到什麼 —— 標籤是**整組覆寫**,送錯就會把別的標籤弄掉。
class _RecordingBackend extends MockBackend {
  final calls = <List<String>?>[];

  @override
  Future<Meeting> updateMeeting(String id,
      {String? title, List<String>? tags}) {
    calls.add(tags);
    return super.updateMeeting(id, title: title, tags: tags);
  }
}

Future<_RecordingBackend> _pump(WidgetTester tester, Meeting meeting) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final backend = _RecordingBackend();
  // updateMeeting 會查 _meetings,所以要先讓這場存在。
  final created = await _real(tester, () async {
    final m = await backend.createMeeting(title: meeting.title);
    await backend.updateMeeting(m.id, tags: meeting.tags);
    return m;
  });

  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      backendProvider.overrideWithValue(backend),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        // 用剛建立那場的 id,updateMeeting 才查得到。
        body: MeetingTagsRow(meeting: _withId(meeting, created.id)),
      ),
    ),
  ));
  await _settle(tester);
  backend.calls.clear();
  return backend;
}

Meeting _withId(Meeting m, String id) => Meeting(
      id: id,
      title: m.title,
      createdAt: m.createdAt,
      tags: m.tags,
    );

Meeting _meeting(List<String> tags) => Meeting(
      id: 'm001',
      title: '產品週會',
      createdAt: DateTime(2026, 9, 1),
      tags: tags,
    );

void main() {
  testWidgets('沒有標籤時說明用途,不只是一個看不懂的加號', (tester) async {
    await _pump(tester, _meeting(const []));
    expect(find.textContaining('加標籤'), findsOneWidget);
    expect(find.textContaining('助理'), findsOneWidget,
        reason: '標籤是選填的,得讓使用者知道填了有什麼好處才會用');
  });

  testWidgets('已有的標籤都顯示出來', (tester) async {
    await _pump(tester, _meeting(const ['專案會議', '每週會議']));
    expect(find.text('專案會議'), findsOneWidget);
    expect(find.text('每週會議'), findsOneWidget);
    expect(find.text('標籤'), findsOneWidget); // 新增用的 chip
  });

  testWidgets('移除某個標籤時,送出的是「剩下的整組」而不是被移除的那個', (tester) async {
    final backend =
        await _pump(tester, _meeting(const ['專案會議', '每週會議']));

    // 點「專案會議」那顆 chip 上的 ✕。
    final chip = find.ancestor(
      of: find.text('專案會議'),
      matching: find.byType(Row),
    );
    await tester.tap(find.descendant(
        of: chip.first, matching: find.byIcon(Icons.close_rounded)));
    await _settle(tester);

    expect(backend.calls, hasLength(1));
    expect(backend.calls.single, ['每週會議'],
        reason: 'PATCH 的 tags 是整組覆寫 —— 送成 [專案會議] 會把留下的那個弄掉');
  });

  testWidgets('新增標籤:面板可輸入,送出的是舊標籤 + 新標籤', (tester) async {
    final backend = await _pump(tester, _meeting(const ['專案會議']));

    await tester.tap(find.text('標籤'));
    await _settle(tester);
    await tester.enterText(find.byType(TextField), '每週會議');
    await _settle(tester);
    await tester.tap(find.textContaining('加上「每週會議」'));
    await _settle(tester);

    expect(backend.calls.single, ['專案會議', '每週會議']);
  });

  testWidgets('輸入已存在的標籤不會重複送 server', (tester) async {
    final backend = await _pump(tester, _meeting(const ['專案會議']));

    await tester.tap(find.text('標籤'));
    await _settle(tester);
    // 大小寫/空白不同但實質相同 —— server 會去重,App 不該白打一趟。
    await tester.enterText(find.byType(TextField), ' 專案會議 ');
    await _settle(tester);
    await tester.tap(find.textContaining('加上'));
    await _settle(tester);

    expect(backend.calls, isEmpty);
  });

  testWidgets('面板列出用過的標籤與會議數,方便重複使用同一個標籤', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final backend = _RecordingBackend();
    await _real(tester, () async {
      final a = await backend.createMeeting(title: 'A');
      final b = await backend.createMeeting(title: 'B');
      await backend.updateMeeting(a.id, tags: ['專案會議']);
      await backend.updateMeeting(b.id, tags: ['專案會議', '每週會議']);
      return null;
    });

    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        backendProvider.overrideWithValue(backend),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: MeetingTagsRow(meeting: _meeting(const []))),
      ),
    ));
    await _settle(tester);

    await tester.tap(find.textContaining('加標籤'));
    await _settle(tester);

    expect(find.text('用過的標籤'), findsOneWidget);
    expect(find.text('2 場'), findsOneWidget); // 專案會議
    expect(find.text('1 場'), findsOneWidget); // 每週會議
  });

  testWidgets('讀不到既有標籤時仍能自己輸入(不該被擋住)', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        backendProvider.overrideWithValue(_FailingTagsBackend()),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: MeetingTagsRow(meeting: _meeting(const []))),
      ),
    ));
    await _settle(tester);

    await tester.tap(find.textContaining('加標籤'));
    await _settle(tester);
    expect(find.textContaining('讀不到既有標籤'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('TagEditorRow:整組回傳,移除時給的是剩下的', (tester) async {
    List<String>? got;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: TagEditorRow(
          tags: const ['專案會議', '每週會議'],
          onChanged: (t) => got = t,
        ),
      ),
    ));
    await tester.pump();

    final chip = find
        .ancestor(of: find.text('專案會議'), matching: find.byType(Row))
        .first;
    await tester.tap(find.descendant(
        of: chip, matching: find.byIcon(Icons.close_rounded)));
    await tester.pump();

    expect(got, ['每週會議'],
        reason: 'onChanged 一律給整組 —— 呼叫端(含 server PATCH)靠這個語意');
  });
}

class _FailingTagsBackend extends MockBackend {
  @override
  Future<List<MeetingTag>> listTags() async => throw Exception('offline');
}
