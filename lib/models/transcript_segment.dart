/// 逐字稿片段。
///
/// 即時轉錄時 server 透過 `WS /transcribe/stream` 回傳 `{text, isFinal, speaker?}`。
/// `isFinal=false` 為暫定(邊錄邊出),`true` 為 VAD 在停頓處分段後的定稿。
class TranscriptSegment {
  const TranscriptSegment({
    required this.id,
    required this.text,
    required this.isFinal,
    this.speaker,
    this.startMs,
    this.endMs,
  });

  final String id;
  final String text;
  final bool isFinal;

  /// 說話者標籤,例如 "說話者 1";未開 diarization 時為 null。
  final String? speaker;
  final int? startMs;
  final int? endMs;

  TranscriptSegment copyWith({
    String? text,
    bool? isFinal,
    String? speaker,
    int? startMs,
    int? endMs,
  }) {
    return TranscriptSegment(
      id: id,
      text: text ?? this.text,
      isFinal: isFinal ?? this.isFinal,
      speaker: speaker ?? this.speaker,
      startMs: startMs ?? this.startMs,
      endMs: endMs ?? this.endMs,
    );
  }

  factory TranscriptSegment.fromJson(Map<String, dynamic> json) {
    final speakerRaw = json['speaker'];
    String? speakerLabel;
    if (speakerRaw is int) {
      speakerLabel = '說話者 ${speakerRaw + 1}';
    } else if (speakerRaw is String && speakerRaw.isNotEmpty) {
      speakerLabel = speakerRaw;
    }
    return TranscriptSegment(
      id: json['id']?.toString() ??
          '${json['start_ms'] ?? ''}-${json['end_ms'] ?? ''}',
      text: (json['text'] as String?) ?? '',
      isFinal: (json['is_final'] as bool?) ??
          (json['isFinal'] as bool?) ??
          true,
      speaker: speakerLabel,
      startMs: (json['start_ms'] as num?)?.toInt(),
      endMs: (json['end_ms'] as num?)?.toInt(),
    );
  }
}
