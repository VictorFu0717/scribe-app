import 'package:flutter/material.dart';

/// 設計系統:品牌漸層、陰影、間距、圓角等視覺 token。
class AppStyle {
  AppStyle._();

  // ── 圓角 ──
  static const double rSm = 12;
  static const double rMd = 18;
  static const double rLg = 24;
  static const double rXl = 32;

  // ── 間距 ──
  static const double gap = 16;
}

/// 品牌漸層。
class AppGradients {
  AppGradients._();

  /// 主要品牌漸層(靛藍 → 紫)。
  static const brand = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
  );

  /// 錄音(暖紅)。
  static const record = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFB7185), Color(0xFFEF4444)],
  );

  /// 強調(青 → 藍),用於摘要/AI 元素。
  static const accent = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF22D3EE), Color(0xFF3B82F6)],
  );

  /// 依字串挑一組柔和漸層(給會議頭像上色)。
  static LinearGradient forSeed(String seed) {
    final palettes = <List<Color>>[
      [Color(0xFF6366F1), Color(0xFF8B5CF6)], // 靛紫
      [Color(0xFF06B6D4), Color(0xFF3B82F6)], // 青藍
      [Color(0xFFF59E0B), Color(0xFFEF4444)], // 橙紅
      [Color(0xFF10B981), Color(0xFF06B6D4)], // 綠青
      [Color(0xFFEC4899), Color(0xFF8B5CF6)], // 粉紫
      [Color(0xFF14B8A6), Color(0xFF6366F1)], // 藍綠
    ];
    var h = 0;
    for (final c in seed.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    final p = palettes[h % palettes.length];
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: p,
    );
  }
}

/// 柔和陰影(淺色模式用;深色模式改用細邊框)。
class AppShadows {
  AppShadows._();

  static List<BoxShadow> soft(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (dark) return const [];
    return [
      BoxShadow(
        color: const Color(0xFF6366F1).withValues(alpha: 0.06),
        blurRadius: 24,
        offset: const Offset(0, 10),
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.04),
        blurRadius: 6,
        offset: const Offset(0, 2),
      ),
    ];
  }

  static List<BoxShadow> glow(Color color, {double strength = 0.4}) => [
        BoxShadow(
          color: color.withValues(alpha: strength),
          blurRadius: 28,
          spreadRadius: 2,
          offset: const Offset(0, 8),
        ),
      ];
}
