import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_style.dart';
import '../../core/utils/formatters.dart';
import '../../providers/recording_controller.dart';
import '../../providers/settings_controller.dart';
import '../../routing/app_router.dart';
import '../../widgets/level_meter.dart';
import '../../widgets/recording_orb.dart';
import '../../widgets/soft_card.dart';
import '../../widgets/transcript_view.dart';

class RecordingScreen extends ConsumerStatefulWidget {
  const RecordingScreen({super.key});

  @override
  ConsumerState<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends ConsumerState<RecordingScreen> {
  late final TextEditingController _titleCtrl =
      TextEditingController(text: '會議 ${Formatters.dateTime(DateTime.now())}');

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final title =
        _titleCtrl.text.trim().isEmpty ? '未命名會議' : _titleCtrl.text.trim();
    await ref.read(recordingControllerProvider.notifier).start(title: title);
  }

  Future<void> _stop() async {
    final id = await ref.read(recordingControllerProvider.notifier).stop();
    if (!mounted) return;
    if (id != null) {
      context.pushReplacement(Routes.meeting(id));
    } else {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(recordingControllerProvider);
    final settings = ref.watch(settingsProvider);

    ref.listen(recordingControllerProvider.select((s) => s.error), (_, err) {
      if (err != null && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(err)));
      }
    });

    final isActive = state.isActive;

    return PopScope(
      canPop: !isActive,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await _confirmStop();
        if (leave == true) await _stop();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(isActive ? '錄音中' : '新錄音')),
        body: SafeArea(
          child: isActive ? _buildActive(state) : _buildIdle(settings, state),
        ),
      ),
    );
  }

  Widget _buildIdle(Settings settings, RecordingState state) {
    final scheme = Theme.of(context).colorScheme;
    final starting = state.phase == RecordingPhase.starting;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          SoftCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: '會議標題',
                prefixIcon: Icon(Icons.title_rounded),
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: 16),
          _ModeChips(settings: settings),
          const Spacer(),
          RecordingOrb(
            recording: false,
            size: 104,
            onTap: starting ? null : _start,
          ),
          const SizedBox(height: 28),
          if (starting)
            const Text('準備中…')
          else
            Text('點擊開始錄音',
                style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(
            settings.streamingTranscription ? '即時逐字稿 · 邊錄邊出字' : '整檔上傳 · 錄完後轉錄',
            style: TextStyle(color: scheme.outline, fontSize: 13),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildActive(RecordingState state) {
    final scheme = Theme.of(context).colorScheme;
    final paused = state.phase == RecordingPhase.paused;
    final finalizing = state.phase == RecordingPhase.finalizing;

    return Column(
      children: [
        const SizedBox(height: 8),
        _StatusPill(paused: paused, finalizing: finalizing),
        const SizedBox(height: 14),
        Text(
          Formatters.duration(state.elapsed),
          style: TextStyle(
            fontSize: 52,
            fontFeatures: const [FontFeature.tabularFigures()],
            fontWeight: FontWeight.w300,
            letterSpacing: 1,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        Text(state.title,
            style: TextStyle(color: scheme.outline),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: LevelMeter(level: state.level, active: !paused),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppStyle.rXl)),
            ),
            child: TranscriptView(
              segments: state.finalSegments,
              partial: state.partial,
              autoScroll: true,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              emptyHint: '開始說話後,逐字稿會即時出現…',
            ),
          ),
        ),
        Container(
          color: scheme.surfaceContainerLow,
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _CircleAction(
                icon: paused ? Icons.mic_rounded : Icons.pause_rounded,
                label: paused ? '繼續' : '暫停',
                onTap: finalizing
                    ? null
                    : () => ref
                        .read(recordingControllerProvider.notifier)
                        .pauseResume(),
              ),
              RecordingOrb(
                recording: true,
                level: state.level,
                size: 80,
                onTap: finalizing ? null : _stop,
              ),
              _CircleAction(
                icon: Icons.check_rounded,
                label: '完成',
                onTap: finalizing ? null : _stop,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<bool?> _confirmStop() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('結束錄音?'),
        content: const Text('離開將停止並儲存這場錄音。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('繼續錄音')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('停止並儲存')),
        ],
      ),
    );
  }
}

class _StatusPill extends StatefulWidget {
  const _StatusPill({required this.paused, required this.finalizing});
  final bool paused;
  final bool finalizing;

  @override
  State<_StatusPill> createState() => _StatusPillState();
}

class _StatusPillState extends State<_StatusPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = widget.finalizing
        ? '收尾中'
        : (widget.paused ? '已暫停' : '錄音中');
    final color = widget.paused || widget.finalizing
        ? scheme.outline
        : const Color(0xFFEF4444);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppStyle.rXl),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: widget.paused || widget.finalizing
                ? const AlwaysStoppedAnimation(1.0)
                : _c,
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            ),
          ),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w700, fontSize: 13)),
        ],
      ),
    );
  }
}

class _ModeChips extends ConsumerWidget {
  const _ModeChips({required this.settings});
  final Settings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        FilterChip(
          label: const Text('說話者辨識'),
          avatar: const Icon(Icons.groups_outlined, size: 18),
          selected: settings.diarization,
          onSelected: (v) =>
              ref.read(settingsProvider.notifier).setDiarization(v),
        ),
        if (settings.diarization)
          ActionChip(
            avatar: const Icon(Icons.numbers_rounded, size: 18),
            label: Text(settings.speakerCount == null
                ? '人數:自動'
                : '人數:${settings.speakerCount}'),
            onPressed: () => _pickSpeakerCount(context, ref, settings),
          ),
      ],
    );
  }

  Future<void> _pickSpeakerCount(
      BuildContext context, WidgetRef ref, Settings settings) async {
    final result = await showModalBottomSheet<int?>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('指定說話者人數',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            ListTile(
              title: const Text('自動偵測'),
              onTap: () => Navigator.pop(ctx, -1),
            ),
            for (var n = 2; n <= 8; n++)
              ListTile(title: Text('$n 人'), onTap: () => Navigator.pop(ctx, n)),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (result == null) return;
    ref
        .read(settingsProvider.notifier)
        .setSpeakerCount(result == -1 ? null : result);
  }
}

class _CircleAction extends StatelessWidget {
  const _CircleAction({required this.icon, required this.label, this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: scheme.surfaceContainerHighest,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Icon(icon,
                  size: 26,
                  color: onTap == null ? scheme.outlineVariant : scheme.onSurface),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: TextStyle(fontSize: 12, color: scheme.outline)),
      ],
    );
  }
}
