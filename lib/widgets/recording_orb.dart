import 'package:flutter/material.dart';

import '../core/theme/app_style.dart';

/// 錄音球:中央漸層圓 + 隨音量脈動的同心光環。
/// [recording] 為 true 時顯示停止方塊並脈動;否則顯示麥克風。
class RecordingOrb extends StatefulWidget {
  const RecordingOrb({
    super.key,
    required this.recording,
    this.level = 0,
    this.size = 96,
    this.onTap,
  });

  final bool recording;
  final double level; // 0..1
  final double size;
  final VoidCallback? onTap;

  @override
  State<RecordingOrb> createState() => _RecordingOrbState();
}

class _RecordingOrbState extends State<RecordingOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const grad = AppGradients.record;
    final ringExtent = widget.size * 0.9;
    return SizedBox(
      width: widget.size + ringExtent,
      height: widget.size + ringExtent,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          final breathe = widget.recording ? _c.value : 0.0;
          return Stack(
            alignment: Alignment.center,
            children: [
              // 兩層光環,依音量放大。
              _ring(1, breathe, grad.colors.last, ringExtent),
              _ring(0.55, breathe, grad.colors.first, ringExtent),
              child!,
            ],
          );
        },
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: grad,
              boxShadow: AppShadows.glow(grad.colors.last, strength: 0.5),
            ),
            child: Icon(
              widget.recording ? Icons.stop_rounded : Icons.mic_rounded,
              color: Colors.white,
              size: widget.size * 0.42,
            ),
          ),
        ),
      ),
    );
  }

  Widget _ring(double phase, double breathe, Color color, double extent) {
    // 音量 + 呼吸動畫共同決定放大幅度。
    final t = ((breathe + phase) % 1.0);
    final base = widget.recording ? (0.4 + widget.level * 0.6) : 0.0;
    final scale = 1 + extent / widget.size * (0.2 + 0.8 * t) * base;
    final opacity = widget.recording ? (1 - t) * (0.35 + widget.level * 0.4) : 0.0;
    return Opacity(
      opacity: opacity.clamp(0.0, 1.0),
      child: Container(
        width: widget.size * scale,
        height: widget.size * scale,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.18),
        ),
      ),
    );
  }
}
