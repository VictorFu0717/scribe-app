import 'package:intl/intl.dart';

/// 繁中(台灣)格式化工具。
class Formatters {
  Formatters._();

  static final _dateFmt = DateFormat('yyyy/MM/dd HH:mm', 'zh_TW');
  static final _dayFmt = DateFormat('M月d日 EEEE', 'zh_TW');

  static String dateTime(DateTime dt) => _dateFmt.format(dt.toLocal());

  static String day(DateTime dt) => _dayFmt.format(dt.toLocal());

  static String relativeDay(DateTime dt) {
    final now = DateTime.now();
    final d = DateTime(dt.year, dt.month, dt.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(d).inDays;
    if (diff == 0) return '今天';
    if (diff == 1) return '昨天';
    if (diff == 2) return '前天';
    return _dayFmt.format(dt.toLocal());
  }

  static String duration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    if (h > 0) return '$h:${two(m)}:${two(s)}';
    return '${two(m)}:${two(s)}';
  }

  static String durationSeconds(int? seconds) =>
      seconds == null ? '--:--' : duration(Duration(seconds: seconds));
}
