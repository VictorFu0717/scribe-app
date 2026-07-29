/// 會議狀態。對應 server 生命週期:錄音中 → 轉錄中 → 就緒。
enum MeetingStatus {
  recording,
  uploading,
  transcribing,
  processing,
  ready,
  error;

  static MeetingStatus fromString(String? s) {
    switch (s) {
      case 'recording':
        return MeetingStatus.recording;
      case 'uploading':
        return MeetingStatus.uploading;
      case 'transcribing':
        return MeetingStatus.transcribing;
      case 'processing':
        return MeetingStatus.processing;
      case 'ready':
        return MeetingStatus.ready;
      case 'error':
        return MeetingStatus.error;
      default:
        return MeetingStatus.ready;
    }
  }

  String get label {
    switch (this) {
      case MeetingStatus.recording:
        return '錄音中';
      case MeetingStatus.uploading:
        return '上傳中';
      case MeetingStatus.transcribing:
        return '轉錄中';
      case MeetingStatus.processing:
        return '處理中';
      case MeetingStatus.ready:
        return '就緒';
      case MeetingStatus.error:
        return '錯誤';
    }
  }
}

/// 一場會議。對應 `GET /meetings/{id}`。
class Meeting {
  const Meeting({
    required this.id,
    required this.title,
    required this.createdAt,
    this.durationSec,
    this.status = MeetingStatus.ready,
    this.hasSummary = false,
    this.remoteAudioUrl,
    this.localAudioPath,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final int? durationSec;
  final MeetingStatus status;
  final bool hasSummary;

  /// server 端音檔位址(若有留存)。
  final String? remoteAudioUrl;

  /// 本地錄音檔路徑(錄製當下暫存,用於播放與防斷線)。
  final String? localAudioPath;

  Duration? get duration =>
      durationSec == null ? null : Duration(seconds: durationSec!);

  Meeting copyWith({
    String? title,
    int? durationSec,
    MeetingStatus? status,
    bool? hasSummary,
    String? remoteAudioUrl,
    String? localAudioPath,
  }) {
    return Meeting(
      id: id,
      title: title ?? this.title,
      createdAt: createdAt,
      durationSec: durationSec ?? this.durationSec,
      status: status ?? this.status,
      hasSummary: hasSummary ?? this.hasSummary,
      remoteAudioUrl: remoteAudioUrl ?? this.remoteAudioUrl,
      localAudioPath: localAudioPath ?? this.localAudioPath,
    );
  }

  factory Meeting.fromJson(Map<String, dynamic> json) {
    return Meeting(
      id: json['id'].toString(),
      title: (json['title'] as String?) ?? '未命名會議',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      durationSec: (json['duration_sec'] as num?)?.toInt(),
      status: MeetingStatus.fromString(json['status'] as String?),
      hasSummary: (json['has_summary'] as bool?) ?? (json['summary'] != null),
      remoteAudioUrl: json['audio_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'created_at': createdAt.toIso8601String(),
        if (durationSec != null) 'duration_sec': durationSec,
        'status': status.name,
        'has_summary': hasSummary,
        if (remoteAudioUrl != null) 'audio_url': remoteAudioUrl,
      };
}
