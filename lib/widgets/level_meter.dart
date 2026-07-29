import 'dart:math';

import 'package:flutter/material.dart';

import '../core/theme/app_style.dart';

/// 有生命力的漸層波形:每根長條有自己的相位,整體振幅由目前音量 [level] 驅動。
class LevelMeter extends StatefulWidget {
  const LevelMeter({
    super.key,
    required this.level,
    this.active = true,
    this.bars = 32,
    this.height = 64,
    this.gradient = AppGradients.record,
  });

  final double level; // 0..1
  final bool active;
  final int bars;
  final double height;
  final Gradient gradient;

  @override
  State<LevelMeter> createState() => _LevelMeterState();
}

class _LevelMeterState extends State<LevelMeter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  double _smooth = 0;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 平滑音量,避免抖動。
    _smooth = _smooth * 0.7 + widget.level * 0.3;
    return SizedBox(
      height: widget.height,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(widget.bars, (i) {
              // 中央高、兩側低的包絡。
              final envelope =
                  1 - (i - (widget.bars - 1) / 2).abs() / widget.bars;
              final wobble =
                  (sin(_c.value * 2 * pi + i * 0.5) + 1) / 2; // 0..1
              final amp = widget.active
                  ? (0.08 + (0.15 + _smooth * 0.85) * envelope * wobble)
                  : 0.04;
              final h = (widget.height * amp).clamp(3.0, widget.height);
              return Container(
                width: 3.5,
                height: h,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  gradient: widget.active ? widget.gradient : null,
                  color: widget.active ? null : scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
