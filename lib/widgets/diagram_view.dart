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
/// 高度由頁面渲染完回報,而不是給一個固定值:圖的大小事先不知道,寫死不是被裁掉
/// 就是在下面留一大塊空白。
class DiagramView extends StatefulWidget {
  const DiagramView({
    super.key,
    required this.diagram,
    this.interactive = false,
    this.maxHeight = 420,
  });

  final MeetingDiagram diagram;

  /// 可否縮放/捲動。聊天氣泡內關閉(會跟列表搶手勢),全螢幕檢視才開。
  final bool interactive;

  /// 氣泡內的高度上限;超過就讓使用者點開全螢幕看。
  final double maxHeight;

  @override
  State<DiagramView> createState() => _DiagramViewState();
}

class _DiagramViewState extends State<DiagramView> {
  WebViewController? _controller;
  double _height = 160;
  bool _ready = false;
  String? _error;

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
          // 一點點高度變化不值得重建(渲染後 requestAnimationFrame 會多報幾次)。
          if (h != null && h > 0 && (h - _height).abs() > 2) {
            if (mounted) setState(() => _height = h);
          }
        case 'error':
          if (mounted) {
            setState(() => _error = j['message']?.toString() ?? '圖表語法有誤');
          }
        case 'ok':
          if (mounted && _error != null) setState(() => _error = null);
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
    await c.runJavaScript(
      'window.renderDiagram(${jsonEncode(widget.diagram.code)}, $dark);',
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

    final height =
        widget.interactive ? _height : _height.clamp(80.0, widget.maxHeight);
    return SizedBox(
      height: height,
      child: WebViewWidget(
        controller: _controller!,
        // 氣泡內要把手勢全讓給外層列表(空集合),否則圖會把捲動吃掉;
        // 全螢幕檢視才讓 WebView 自己收手勢(縮放/平移)。
        gestureRecognizers: widget.interactive
            ? <Factory<OneSequenceGestureRecognizer>>{
                Factory<OneSequenceGestureRecognizer>(
                    EagerGestureRecognizer.new),
              }
            : const <Factory<OneSequenceGestureRecognizer>>{},
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
