import 'meeting_diagram.dart';

enum ChatRole { system, user, assistant }

/// 個人助理對話訊息。
///
/// `thinking` 保存推理模型 `<think>...</think>` 內容,UI 預設隱藏、可展開
/// (交接文件第 2 節:要能隱藏 think 區塊只顯示答案)。
class ChatMessage {
  ChatMessage({
    required this.role,
    required this.content,
    this.thinking,
    this.isStreaming = false,
    List<MeetingDiagram>? diagrams,
  }) : diagrams = diagrams ?? [];

  final ChatRole role;
  String content;
  String? thinking;
  bool isStreaming;

  /// 助理在這則回答裡畫出來的圖(可能不只一張)。
  final List<MeetingDiagram> diagrams;

  bool get isUser => role == ChatRole.user;

  Map<String, dynamic> toWireJson() => {
        'role': role.name,
        'content': content,
      };

  ChatMessage copyWith({
    String? content,
    String? thinking,
    bool? isStreaming,
    List<MeetingDiagram>? diagrams,
  }) {
    return ChatMessage(
      role: role,
      content: content ?? this.content,
      thinking: thinking ?? this.thinking,
      isStreaming: isStreaming ?? this.isStreaming,
      diagrams: diagrams ?? this.diagrams,
    );
  }
}
