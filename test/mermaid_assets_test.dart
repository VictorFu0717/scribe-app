import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 這組測試守住「為什麼不能把 mermaid.js 內嵌進 HTML」。
///
/// 實測踩過:把 bundle 內嵌到 `<script>…</script>` 後,`mermaid` 根本沒被定義 ——
/// 因為 bundle 裡有 `<!--` 序列,HTML 解析器在 script 內遇到它會進入 escaped
/// 狀態,把後面整段(含結尾的 globalThis 指派)吃掉。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('renderer.html 以外部 src 載入 mermaid,不是預期被內嵌', () async {
    final html =
        await rootBundle.loadString('assets/mermaid/renderer.html');
    expect(html, contains('<script src="mermaid.min.js"></script>'),
        reason: '內嵌會被 HTML 解析器吃掉(見本檔說明),必須走外部檔案');
    // 渲染介面與高度回報是 Dart 端依賴的契約。
    expect(html, contains('window.renderDiagram'));
    expect(html, contains('DiagramChannel'));
    // 原始碼由 LLM 產生,不能讓它在 WebView 裡執行 JS。
    expect(html, contains("securityLevel: 'strict'"));
  });

  test('打包的 mermaid.js 會把自己掛到 globalThis', () async {
    final js = await rootBundle.loadString('assets/mermaid/mermaid.min.js');
    expect(js, contains('globalThis["mermaid"]'),
        reason: '渲染器直接用全域 mermaid;換成 ESM-only 的檔案會整個失效');
    expect(js.length, greaterThan(1000000), reason: '看起來不是完整的 bundle');
  });

  test('bundle 確實含有會破壞內嵌的序列(說明上一條規則的理由)', () async {
    final js = await rootBundle.loadString('assets/mermaid/mermaid.min.js');
    expect(js, contains('<!--'),
        reason: '這正是不能內嵌的原因;哪天不再含有也不代表可以內嵌');
  });
}
