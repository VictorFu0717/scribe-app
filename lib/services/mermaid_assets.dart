import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// 把打包在 App 內的 Mermaid 渲染器解到磁碟,回傳 HTML 的路徑。
///
/// 為什麼要落地成檔案,而不是把 JS 內嵌進 HTML 字串([WebViewController.loadHtmlString]):
/// mermaid 的 bundle 裡含有 `<!--` 這類序列(如字串 `"<!-->"`、正規表示式字面值),
/// HTML 解析器在 `<script>` 內遇到它會進入 escaped 狀態,導致整段腳本被吃掉 ——
/// 實測內嵌後 `mermaid` 根本沒定義。改成 `<script src="mermaid.min.js">` 由瀏覽器
/// 當成獨立資源載入就沒有這個問題。
class MermaidAssets {
  MermaidAssets._();

  static const _htmlAsset = 'assets/mermaid/renderer.html';
  static const _jsAsset = 'assets/mermaid/mermaid.min.js';

  /// 解壓只做一次;多個圖同時出現時共用同一個 Future(避免互相覆寫寫到一半的檔案)。
  static Future<String>? _pending;

  static Future<String> htmlPath() => _pending ??= _extract();

  static Future<String> _extract() async {
    try {
      final base = await getApplicationSupportDirectory();
      final dir = Directory('${base.path}/mermaid');
      if (!dir.existsSync()) dir.createSync(recursive: true);

      final html = File('${dir.path}/renderer.html');
      final js = File('${dir.path}/mermaid.min.js');

      // 比長度就夠:這兩個檔只會隨 App 更新而變,不會被外部改動。
      // 每次都重寫 3.4MB 會讓第一張圖明顯變慢。
      final htmlData = await rootBundle.loadString(_htmlAsset);
      if (!html.existsSync() || html.lengthSync() != htmlData.length) {
        await html.writeAsString(htmlData, flush: true);
      }
      final jsData = await rootBundle.load(_jsAsset);
      if (!js.existsSync() || js.lengthSync() != jsData.lengthInBytes) {
        await js.writeAsBytes(jsData.buffer.asUint8List(), flush: true);
      }
      return html.path;
    } catch (e) {
      _pending = null; // 失敗不要把錯誤結果快取住,下次還能再試
      rethrow;
    }
  }
}
