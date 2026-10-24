import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/meeting_diagram.dart';
import '../services/mermaid_assets.dart';

/// 渲染一張 Mermaid 圖。
///
/// 為什麼用 WebView:Mermaid 是 JS 專案,Dart 沒有等價的渲染器。mermaid.js 與這份
/// HTML 都**打包在 App 內**(見 pubspec 的 assets),不吃 CDN —— server 在內網
/// (Tailscale/OpenVPN),使用者常常連不到外網。
///
/// 兩種模式:
///  - 縮圖(聊天氣泡內):整張圖等比縮到 [maxHeight] 以內,**只負責顯示**,
///    不收任何手勢(點擊由外層開全螢幕、上下拖曳交給聊天列表)。高度由頁面
///    渲染完回報,而不是寫死 —— 寫死不是被裁掉就是留一大塊空白。
///  - 全螢幕([interactive]):WebView 填滿父元件,捲動與雙指縮放**交給 WebView
///    自己處理**。先前把它包在 Flutter 的捲動容器裡,手勢被 WebView 吃掉、
///    外層又捲不動,放大後只看得到上半部。
class DiagramView extends StatefulWidget {
  const DiagramView({
    super.key,
    required this.diagram,
    this.interactive = false,
    this.maxHeight = 560,
  });

  final MeetingDiagram diagram;

  /// 全螢幕模式:填滿父元件,可捲動與縮放。
  final bool interactive;

  /// 縮圖的高度上限;圖更高時整張等比縮小,並提示「點擊放大」。
  final double maxHeight;

  @override
  State<DiagramView> createState() => _DiagramViewState();
}

class _DiagramViewState extends State<DiagramView> {
  WebViewController? _controller;
  double _height = 200;
  bool _ready = false;
  String? _error;

  /// 已經畫出來了(在那之前蓋一層載入中,不讓使用者看到空白的畫布)。
  bool _drawn = false;

  /// 縮圖被縮得比較小,要提示可以點開放大。
  bool _shrunk = false;

  /// 已送去渲染的內容 + 主題,避免重複渲染同一張圖。
  String? _rendered;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(DiagramView old) {
    super.didUpdateWidget(old);
    if (old.diagram.code != widget.diagram.code) _render();
  }

  Future<void> _init() async {
    try {
      // 從檔案載入而非內嵌字串 —— 原因見 MermaidAssets 的說明(內嵌會讓
      // mermaid 的 bundle 被 HTML 解析器吃掉)。
      final path = await MermaidAssets.htmlPath();

      final c = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        // 只有全螢幕才允許雙指縮放;縮圖本來就不收手勢,關掉免得意外觸發
        ..enableZoom(widget.interactive)
        // 透明背景:圖要融進聊天氣泡,白底方塊很突兀(深色模式尤其明顯)。
        ..setBackgroundColor(Colors.transparent)
        ..addJavaScriptChannel('DiagramChannel',
            onMessageReceived: _onJsMessage)
        ..setNavigationDelegate(NavigationDelegate(
          onPageFinished: (_) {
            _ready = true;
            _render();
          },
          // 只允許載入我們自己解出來的那份檔案;圖裡不該有連結,
          // 真有也不讓它把 WebView 導走(原始碼是 LLM 產的)。
          onNavigationRequest: (r) =>
              r.url.startsWith('file:') || r.url.startsWith('about:')
                  ? NavigationDecision.navigate
                  : NavigationDecision.prevent,
        ));
      await c.loadFile(path);
      if (mounted) setState(() => _controller = c);
    } catch (e) {
      if (mounted) setState(() => _error = '圖表元件載入失敗:$e');
    }
  }

  void _onJsMessage(JavaScriptMessage m) {
    try {
      final j = jsonDecode(m.message);
      if (j is! Map) return;
      switch (j['type']) {
        case 'size':
          final h = (j['height'] as num?)?.toDouble();
          final shrunk = j['shrunk'] == true;
          // 一點點高度變化不值得重建(視窗尺寸變動時會多報幾次)。
          if (h != null && h > 0 && ((h - _height).abs() > 2 || shrunk != _shrunk)) {
            if (mounted) {
              setState(() {
                _height = h;
                _shrunk = shrunk;
              });
            }
          }
        case 'error':
          if (mounted) {
            setState(() => _error = j['message']?.toString() ?? '圖表語法有誤');
          }
        case 'ok':
          if (mounted) {
            setState(() {
              _drawn = true;
              _error = null;
            });
          }
      }
    } catch (_) {
      // JS 傳回來的東西壞掉不該讓畫面爆掉。
    }
  }

  Future<void> _render() async {
    final c = _controller;
    if (c == null || !_ready) return;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final key = '${widget.diagram.code}|$dark';
    if (key == _rendered) return;
    _rendered = key;
    final opts = jsonEncode({
      'mode': widget.interactive ? 'full' : 'thumb',
      'maxHeight': widget.maxHeight,
      // 關係圖會依此改用彩色膠囊,並在直立螢幕上改成上下展開
      'kind': widget.diagram.kind,
    });
    await c.runJavaScript(
      'window.renderDiagram(${jsonEncode(widget.diagram.code)}, $dark, $opts);',
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _render(); // 亮/深色切換時重畫
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_error != null) {
      return _DiagramError(message: _error!, code: widget.diagram.code);
    }
    if (_controller == null) {
      return SizedBox(
        height: 120,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: scheme.primary),
          ),
        ),
      );
    }

    final loading = _drawn
        ? null
        : Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: scheme.primary),
            ),
          );

    if (widget.interactive) {
      // 填滿父元件;捲動與縮放全交給 WebView(外層不能再包捲動容器)。
      return Stack(
        children: [
          Positioned.fill(
            child: WebViewWidget(
              controller: _controller!,
              gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                Factory<OneSequenceGestureRecognizer>(
                    EagerGestureRecognizer.new),
              },
            ),
          ),
          ?loading,
        ],
      );
    }

    return SizedBox(
      height: _height.clamp(80.0, widget.maxHeight),
      child: Stack(
        children: [
          // 縮圖只負責顯示:IgnorePointer 讓 WebView 完全收不到觸控,
          // 點擊由外層開全螢幕、上下拖曳交給聊天列表捲動。
          Positioned.fill(
            child: IgnorePointer(
              child: WebViewWidget(controller: _controller!),
            ),
          ),
          ?loading,
          if (_shrunk && _drawn)
            Positioned(
              right: 8,
              bottom: 8,
              child: IgnorePointer(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: scheme.inverseSurface.withValues(alpha: 0.78),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.zoom_in_rounded,
                          size: 14, color: scheme.onInverseSurface),
                      const SizedBox(width: 3),
                      Text('點擊放大',
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: scheme.onInverseSurface)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 圖畫不出來時顯示原因與原始碼 —— 留白畫面最糟,使用者只會以為當掉。
class _DiagramError extends StatelessWidget {
  const _DiagramError({required this.message, required this.code});

  final String message;
  final String code;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.broken_image_outlined, size: 16, color: scheme.error),
              const SizedBox(width: 6),
              Expanded(
                child: Text('這張圖畫不出來',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: scheme.error)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(message,
              style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
              maxLines: 3,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
          Text('可以請助理「重畫一次」,或複製原始碼自行檢查:',
              style: TextStyle(fontSize: 11.5, color: scheme.outline)),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: code));
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已複製圖表原始碼')));
              },
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text('複製原始碼', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
