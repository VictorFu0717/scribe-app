import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../core/utils/formatters.dart';
import '../providers/service_providers.dart';
import '../services/audio_player_service.dart';

/// 會議錄音播放列(本地檔優先,否則播 server 遠端音檔)。
class AudioPlayerBar extends ConsumerStatefulWidget {
  const AudioPlayerBar({
    super.key,
    required this.meetingId,
    this.localPath,
    this.remoteUri,
    this.headers,
  });

  /// 這個播放列屬於哪一場會議。播放器是 App 層級共用的,需靠它辨識目前
  /// 載入的音源是哪一場,避免在別場會議誤觸而播出上一場的錄音。
  final String meetingId;

  final String? localPath;
  final Uri? remoteUri;
  final Map<String, String>? headers;

  @override
  ConsumerState<AudioPlayerBar> createState() => _AudioPlayerBarState();
}

class _AudioPlayerBarState extends ConsumerState<AudioPlayerBar> {
  bool _loaded = false;
  bool _unavailable = false;
  AudioPlayerService? _svc;

  @override
  void initState() {
    super.initState();
    _svc = ref.read(audioPlayerProvider);
    _load();
  }

  @override
  void dispose() {
    // 離開頁面時停止播放(播放器是 App 層級共用 singleton,不會自己停)。
    _svc?.stop();
    super.dispose();
  }

  Future<void> _load() async {
    final svc = _svc!; // initState 已設定
    try {
      final ok = await svc.loadForMeeting(
        meetingId: widget.meetingId,
        localPath: widget.localPath,
        remoteUri: widget.remoteUri,
        headers: widget.headers,
      );
      if (mounted) {
        setState(() {
          _loaded = ok;
          _unavailable = !ok;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _unavailable = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_unavailable) {
      return Container(
        padding: const EdgeInsets.all(12),
        alignment: Alignment.center,
        child: Text('沒有可播放的音檔',
            style: TextStyle(color: scheme.outline, fontSize: 13)),
      );
    }
    if (!_loaded) {
      return const SizedBox(
        height: 64,
        child: Center(
            child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }

    final svc = ref.read(audioPlayerProvider);
    final player = svc.player;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: StreamBuilder<Duration>(
        stream: svc.positionStream,
        builder: (context, posSnap) {
          final pos = posSnap.data ?? Duration.zero;
          final dur = player.duration ?? Duration.zero;
          return Row(
            children: [
              StreamBuilder<PlayerState>(
                stream: svc.playerStateStream,
                builder: (context, stateSnap) {
                  final playing = stateSnap.data?.playing ?? false;
                  final completed = stateSnap.data?.processingState ==
                      ProcessingState.completed;
                  return IconButton.filledTonal(
                    icon: Icon(playing
                        ? Icons.pause
                        : (completed ? Icons.replay : Icons.play_arrow)),
                    onPressed: () async {
                      if (completed) {
                        await svc.seek(Duration.zero);
                        await svc.play();
                      } else if (playing) {
                        await svc.pause();
                      } else {
                        await svc.play();
                      }
                    },
                  );
                },
              ),
              Expanded(
                child: Slider(
                  value: pos.inMilliseconds
                      .clamp(0, dur.inMilliseconds)
                      .toDouble(),
                  max: (dur.inMilliseconds == 0 ? 1 : dur.inMilliseconds)
                      .toDouble(),
                  onChanged: (v) =>
                      svc.seek(Duration(milliseconds: v.toInt())),
                ),
              ),
              Text('${Formatters.duration(pos)} / ${Formatters.duration(dur)}',
                  style: TextStyle(fontSize: 12, color: scheme.outline)),
              const SizedBox(width: 8),
            ],
          );
        },
      ),
    );
  }
}
