/// 待辦事項(負責人 + 期限)。
class ActionItem {
  const ActionItem({required this.task, this.owner, this.due});

  final String task;
  final String? owner;
  final String? due;

  factory ActionItem.fromJson(Map<String, dynamic> json) => ActionItem(
        task: (json['task'] ?? json['item'] ?? '').toString(),
        owner: json['owner'] as String?,
        due: (json['due'] ?? json['deadline'])?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'task': task,
        if (owner != null) 'owner': owner,
        if (due != null) 'due': due,
      };
}

/// 結構化會議摘要(繁中固定結構)。
///
/// 交接文件第 2 節:會議摘要 / 討論重點 / 決議事項 / 待辦事項(負責人+期限)/
/// 後續追蹤。摘要以 SSE 串流方式產出。
class MeetingSummary {
  const MeetingSummary({
    this.overview = '',
    this.keyPoints = const [],
    this.decisions = const [],
    this.actionItems = const [],
    this.followUps = const [],
  });

  final String overview; // 會議摘要
  final List<String> keyPoints; // 討論重點
  final List<String> decisions; // 決議事項
  final List<ActionItem> actionItems; // 待辦事項
  final List<String> followUps; // 後續追蹤

  bool get isEmpty =>
      overview.isEmpty &&
      keyPoints.isEmpty &&
      decisions.isEmpty &&
      actionItems.isEmpty &&
      followUps.isEmpty;

  factory MeetingSummary.fromJson(Map<String, dynamic> json) {
    List<String> strList(dynamic v) => v is List
        ? v.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
        : const [];
    final rawActions = json['action_items'] ?? json['actionItems'];
    final actionItems = rawActions is List
        ? rawActions
            .map((e) => e is Map<String, dynamic>
                ? ActionItem.fromJson(e)
                : ActionItem(task: e.toString()))
            .toList()
        : <ActionItem>[];
    return MeetingSummary(
      overview: (json['overview'] ?? json['summary'] ?? '').toString(),
      keyPoints: strList(json['key_points'] ?? json['keyPoints']),
      decisions: strList(json['decisions']),
      actionItems: actionItems,
      followUps: strList(json['follow_ups'] ?? json['followUps']),
    );
  }

  Map<String, dynamic> toJson() => {
        'overview': overview,
        'key_points': keyPoints,
        'decisions': decisions,
        'action_items': actionItems.map((e) => e.toJson()).toList(),
        'follow_ups': followUps,
      };
}
