/// 助理畫出來的一張圖(Mermaid 原始碼,由 App 端渲染)。
///
/// 對應 server `/assistant/chat` 的獨立 SSE 事件:
/// `{"type":"diagram","meeting_id":..,"kind":..,"code":..,"source":..,"hint"?:..}`
///
/// 圖不走文字串流是刻意的 —— 讓 LLM 把 Mermaid 覆述一遍既浪費 token,
/// 轉抄時又很容易改壞語法。
class MeetingDiagram {
  const MeetingDiagram({
    required this.kind,
    required this.code,
    this.meetingId,
    this.source,
    this.hint,
  });

  /// flow / relation / timeline / mindmap。
  final String kind;

  /// Mermaid 原始碼。
  final String code;

  final String? meetingId;

  /// 畫圖依據:summary(摘要)或 transcript(逐字稿)。
  final String? source;

  /// server 給的補充說明,例如「這場會議還沒有摘要…」。
  final String? hint;

  /// 給使用者看的圖種名稱。
  String get kindLabel => switch (kind) {
        'flow' => '流程圖',
        'relation' => '關係圖',
        'timeline' => '時間軸',
        'mindmap' => '心智圖',
        _ => '圖表',
      };

  /// 依據來源的說明;未知來源回 null。
  String? get sourceLabel => switch (source) {
        'summary' => '依據摘要',
        'transcript' => '依據逐字稿',
        _ => null,
      };

  /// 從 SSE 事件建立;不是合法的 diagram 事件回 null。
  static MeetingDiagram? fromJson(Map<String, dynamic> json) {
    if (json['type'] != 'diagram') return null;
    final code = json['code'];
    // 沒有原始碼就沒有圖可畫 —— 與其渲染出一塊空白,不如當成不存在。
    if (code is! String || code.trim().isEmpty) return null;
    final kind = json['kind'];
    return MeetingDiagram(
      kind: (kind is String && kind.isNotEmpty) ? kind : 'flow',
      code: code.trim(),
      meetingId: json['meeting_id']?.toString(),
      source: json['source'] as String?,
      hint: (json['hint'] as String?)?.trim().isEmpty ?? true
          ? null
          : (json['hint'] as String).trim(),
    );
  }

  Map<String, dynamic> toJson() => {
        'type': 'diagram',
        'kind': kind,
        'code': code,
        if (meetingId != null) 'meeting_id': meetingId,
        if (source != null) 'source': source,
        if (hint != null) 'hint': hint,
      };
}
