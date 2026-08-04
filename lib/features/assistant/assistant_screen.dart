import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_style.dart';
import '../../providers/assistant_controller.dart';
import '../../widgets/chat_bubble.dart';

/// 個人助理。scope='' 表示跨全部會議(agentic RAG);否則限定單一會議。
class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen({
    super.key,
    required this.scope,
    this.title = '個人助理',
    this.embedded = false,
  });

  final String scope;
  final String title;

  /// 是否嵌入在分頁中(嵌入時不顯示自己的 AppBar)。
  final bool embedded;

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _send() {
    final text = _inputCtrl.text;
    if (text.trim().isEmpty) return;
    _inputCtrl.clear();
    ref.read(assistantControllerProvider(widget.scope).notifier).send(text);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent + 120,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(assistantControllerProvider(widget.scope));

    ref.listen(assistantControllerProvider(widget.scope), (_, next) {
      if (next.streaming) _scrollToBottom();
    });

    final scoped = widget.scope.isNotEmpty;

    // 點對話區任一空白處即收起鍵盤(多行輸入框 Enter 是換行、不會自動收)。
    final body = GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.translucent,
      child: Column(
      children: [
        Expanded(
          child: state.messages.isEmpty
              ? _EmptyHint(
                  scoped: scoped,
                  onPick: (q) {
                    _inputCtrl.text = q;
                    _send();
                  },
                )
              : ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  itemCount: state.messages.length,
                  itemBuilder: (_, i) => ChatBubble(message: state.messages[i]),
                ),
        ),
        if (state.error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(state.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        _InputBar(
          controller: _inputCtrl,
          hintText: scoped ? '問問這場會議的內容…' : '問問所有會議的內容…',
          streaming: state.streaming,
          onSend: _send,
          onStop: () => ref
              .read(assistantControllerProvider(widget.scope).notifier)
              .stop(),
        ),
      ],
      ),
    );

    if (widget.embedded) return body;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (state.messages.isNotEmpty)
            IconButton(
              tooltip: '清除對話',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () => ref
                  .read(assistantControllerProvider(widget.scope).notifier)
                  .clear(),
            ),
        ],
      ),
      body: SafeArea(child: body),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.hintText,
    required this.streaming,
    required this.onSend,
    required this.onStop,
  });

  final TextEditingController controller;
  final String hintText;
  final bool streaming;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.fromLTRB(
          12, 8, 12, 8 + MediaQuery.viewInsetsOf(context).bottom),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: hintText,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _SendButton(streaming: streaming, onSend: onSend, onStop: onStop),
        ],
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton(
      {required this.streaming, required this.onSend, required this.onStop});
  final bool streaming;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppGradients.brand,
        boxShadow: AppShadows.glow(AppGradients.brand.colors.last, strength: 0.3),
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: streaming ? onStop : onSend,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Icon(
              streaming ? Icons.stop_rounded : Icons.arrow_upward_rounded,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.scoped, required this.onPick});
  final bool scoped;
  final void Function(String) onPick;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final suggestions = scoped
        ? const ['這場會議的重點是什麼?', '有哪些待辦事項?', '做了哪些決議?']
        : const ['上週有哪些決議?', '目前所有未完成的待辦?', '幫我找關於「架構」的討論'];
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: AppGradients.accent,
                shape: BoxShape.circle,
                boxShadow: AppShadows.glow(
                    AppGradients.accent.colors.last,
                    strength: 0.35),
              ),
              child: const Icon(Icons.auto_awesome,
                  size: 32, color: Colors.white),
            ),
            const SizedBox(height: 16),
            Text(scoped ? '詢問這場會議' : '詢問你的所有會議',
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('會檢索逐字稿與摘要後回答',
                style: TextStyle(color: scheme.outline)),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: suggestions
                  .map((q) => ActionChip(
                        label: Text(q),
                        onPressed: () => onPick(q),
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}
