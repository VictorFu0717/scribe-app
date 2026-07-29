import 'dart:ui';

import 'package:flutter/material.dart';

/// 背景光暈:在畫面角落放兩三個模糊的漸層色團,營造現代感與層次。
class BrandBackground extends StatelessWidget {
  const BrandBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const defaultBlobs = [
      _Blob(Alignment(-1.1, -1.2), Color(0xFF6366F1), 320),
      _Blob(Alignment(1.3, -0.6), Color(0xFF8B5CF6), 280),
      _Blob(Alignment(0.8, 1.2), Color(0xFF22D3EE), 300),
    ];
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      children: [
        Positioned.fill(child: ColoredBox(color: scheme.surface)),
        Positioned.fill(
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
            child: Stack(
              children: [
                for (final b in defaultBlobs)
                  Align(
                    alignment: b.alignment,
                    child: Container(
                      width: b.size,
                      height: b.size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color:
                            b.color.withValues(alpha: dark ? 0.22 : 0.30),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _Blob {
  const _Blob(this.alignment, this.color, this.size);
  final Alignment alignment;
  final Color color;
  final double size;
}
