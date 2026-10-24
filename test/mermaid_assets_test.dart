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

  test('套用自訂主題,不是 mermaid 的預設外觀', () async {
    final html = await rootBundle.loadString('assets/mermaid/renderer.html');
    // theme 必須是 base —— 'default' 吃不到 themeVariables,整張圖會變回
    // 細框灰方塊(使用者回報「很陽春」就是那個樣子)。
    expect(html, contains("theme: 'base'"));
    expect(html, contains('themeVariables'));
    expect(html, contains('themeCSS'));
    // 品牌色(見 app_theme.dart 的 seed)。
    expect(html, contains('#6366F1'));
    // timeline / mindmap 不吃 primaryColor,一定要有 cScale 系列,
    // 否則那兩種圖會是灰的。
    expect(html, contains("'cScale'"));
    expect(html, contains("'cScaleInv'"));
    // 淺色與深色兩套色盤都要在。
    expect(html, contains('light:'));
    expect(html, contains('dark:'));
  });

  test('svg 寬度規則:可縮小但不放大', () async {
    final html = await rootBundle.loadString('assets/mermaid/renderer.html');
    final rule = RegExp(r'#wrap svg \{[^}]*\}').firstMatch(html)?.group(0) ?? '';
    expect(rule, contains('max-width: 100%'));
    expect(rule, contains('min-width: 0'),
        reason: 'flex 項目預設 min-width:auto,窄螢幕下縮不下去');
    expect(rule, isNot(contains('!important')),
        reason: 'mermaid 的 inline max-width 是「不要放大超過原尺寸」的上限,'
            '蓋掉它小圖會被拉大、字糊掉');
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
