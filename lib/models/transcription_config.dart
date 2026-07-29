/// 轉錄設定:是否啟用說話者辨識(diarization)與指定人數。
///
/// 交接文件第 2 節:diarization 可開關;可「指定人數」(自動常把相近音色併成
/// 一人,手動指定最可靠)。
class TranscriptionConfig {
  const TranscriptionConfig({
    this.diarization = false,
    this.speakerCount,
    this.language = 'zh',
  });

  final bool diarization;

  /// 指定說話者人數;null 代表讓 server 自動判斷。
  final int? speakerCount;

  final String language;

  TranscriptionConfig copyWith({
    bool? diarization,
    int? speakerCount,
    bool clearSpeakerCount = false,
    String? language,
  }) {
    return TranscriptionConfig(
      diarization: diarization ?? this.diarization,
      speakerCount:
          clearSpeakerCount ? null : (speakerCount ?? this.speakerCount),
      language: language ?? this.language,
    );
  }

  Map<String, dynamic> toJson() => {
        'diarization': diarization,
        if (speakerCount != null) 'speaker_count': speakerCount,
        'language': language,
      };

  /// 轉成可附加到 WS / upload URL 的 query 參數。
  Map<String, String> toQueryParameters() => {
        'diarization': diarization.toString(),
        if (speakerCount != null) 'speaker_count': speakerCount.toString(),
        'language': language,
      };
}
