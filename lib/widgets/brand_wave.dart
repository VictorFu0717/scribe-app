import 'dart:math';

import 'package:flutter/material.dart';

import '../core/theme/app_style.dart';

/// 持續跳動的等化器動畫,作為品牌識別(登入/啟動)。
class BrandWave extends StatefulWidget {
  const BrandWave({
    super.key,
    this.size = 72,
    this.bars = 5,
    this.gradient = AppGradients.brand,
  });

  final double size;
  final int bars;
  final Gradient gradient;

  @override
  State<BrandWave> createState() => _BrandWaveState();
}

class _BrandWaveState extends State<BrandWave>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final barW = widget.size / (widget.bars * 2);
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(widget.bars, (i) {
              final phase = i * 0.6;
              final v = (sin(_c.value * 2 * pi + phase) + 1) / 2; // 0..1
              final h = widget.size * (0.28 + 0.62 * v);
              return Container(
                width: barW,
                height: h,
                margin: EdgeInsets.symmetric(horizontal: barW * 0.35),
                decoration: BoxDecoration(
                  gradient: widget.gradient,
                  borderRadius: BorderRadius.circular(barW),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
