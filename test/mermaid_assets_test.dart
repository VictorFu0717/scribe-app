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

  test('縮圖整張縮到放得下且不放大;全螢幕可往下捲', () async {
    final html = await rootBundle.loadString('assets/mermaid/renderer.html');
    // 縮圖:取寬、高兩者的限制,且上限 1(不放大)。先前固定高度,
    // 比較高的圖下半部直接被截掉。
    expect(html, contains('Math.min(1, availW / natW, availH / natH)'));
    // 全螢幕:只符合寬度,不限制高度 —— 比螢幕高就往下捲(實測回報的 bug)。
    expect(html, contains("opts.mode === 'full'"));
    // 全螢幕要能縮小看全貌
    expect(html, contains('minimum-scale=0.25'));
  });

  test('時間軸與心智圖改用直式版面,解析不了才退回 mermaid', () async {
    final html = await rootBundle.loadString('assets/mermaid/renderer.html');
    expect(html, contains('function parseTimeline'));
    expect(html, contains('function parseMindmap'));
    expect(html, contains('if (renderVertical(code, p, wrap))'),
        reason: '直式版面失敗時要接著走 mermaid,不能變空白');
  });

  test('直式版面的文字一律用 textContent(原始碼是 LLM 產的)', () async {
    final html = await rootBundle.loadString('assets/mermaid/renderer.html');
    final start = html.indexOf('function parseTimeline');
    final end = html.indexOf('let last = null;');
    expect(start, greaterThan(0));
    final vertical = html.substring(start, end);
    expect(vertical, isNot(contains('innerHTML')),
        reason: '用 innerHTML 組字串就能被塞進 <img onerror> 之類的東西');
    expect(html, contains('e.textContent = text'));
  });

  test('左右展開的圖在直立螢幕上可改成上下展開', () async {
    final html = await rootBundle.loadString('assets/mermaid/renderer.html');
    expect(html, contains('LR_RE'));
    // 只有明顯比較好才換,本來放得下的圖維持原樣
    expect(html, contains('* 1.15'));
  });

  test('匯出 JPG:淺色白底重畫,HTML 版面用 CSS zoom 放大', () async {
    final html = await rootBundle.loadString('assets/mermaid/renderer.html');
    expect(html, contains('window.exportImage = exportImage'));
    // 匯出一律用淺色主題(要貼進文件、傳到群組,白底最通用)
    final start = html.indexOf('async function exportImage()');
    final body = html.substring(start, html.indexOf('window.exportImage'));
    expect(body, contains('PALETTE.light'));
    // WebKit 裡 foreignObject 內有定位的元素不吃 viewBox 縮放 —— 實測標題被放大、
    // 時間線卻停在 1 倍,疊成一團。HTML 版面必須用 zoom 放大。
    expect(html, contains(r'zoom:${scale}'));
    // 解析度上限:iOS 的 canvas 有面積上限,超過整張會是空白
    expect(html, contains('12e6'));
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
