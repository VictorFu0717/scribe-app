import 'package:flutter/material.dart';

import '../core/theme/app_style.dart';
import '../models/chat_message.dart';

/// 聊天氣泡。assistant 訊息可展開 `<think>` 推理內容(預設隱藏)。
class ChatBubble extends StatefulWidget {
  const ChatBubble({super.key, required this.message});
  final ChatMessage message;

  @override
  State<ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<ChatBubble> {
  bool _showThinking = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final m = widget.message;
    final isUser = m.isUser;

    final textColor = isUser ? Colors.white : scheme.onSurface;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.82),
        margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 12),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
        decoration: BoxDecoration(
          gradient: isUser ? AppGradients.brand : null,
          color: isUser ? null : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isUser ? 18 : 5),
            bottomRight: Radius.circular(isUser ? 5 : 18),
          ),
          boxShadow: isUser
              ? AppShadows.glow(AppGradients.brand.colors.last, strength: 0.22)
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isUser && (m.thinking?.isNotEmpty ?? false)) ...[
              InkWell(
                onTap: () => setState(() => _showThinking = !_showThinking),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _showThinking
                          ? Icons.keyboard_arrow_down
                          : Icons.keyboard_arrow_right,
                      size: 16,
                      color: scheme.outline,
                    ),
                    Text('推理過程',
                        style: TextStyle(
                            fontSize: 12,
                            color: scheme.outline,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
              if (_showThinking)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 4, bottom: 6),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(m.thinking!,
                      style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: scheme.onSurfaceVariant)),
                ),
            ],
            if (m.content.isEmpty && m.isStreaming)
              const _TypingDots()
            else
              SelectableText(
                m.content,
                style: TextStyle(color: textColor, fontSize: 15, height: 1.45),
              ),
          ],
        ),
      ),
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
        ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outline;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final t = (_c.value + i * 0.2) % 1.0;
            final opacity = 0.3 + 0.7 * (1 - (t - 0.5).abs() * 2).clamp(0.0, 1.0);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
              child: Opacity(
                opacity: opacity,
                child: CircleAvatar(radius: 3, backgroundColor: color),
              ),
            );
          }),
        );
      },
    );
  }
}
