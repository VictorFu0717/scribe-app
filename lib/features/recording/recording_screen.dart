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
import '../../widgets/speaker_count_picker.dart';
import '../../widgets/soft_card.dart';
import '../../providers/translation_models_controller.dart';
import '../../services/on_device_translator.dart';
import '../../widgets/language_picker.dart';
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
          Text('即時逐字稿 · 邊錄邊出字',
              style: TextStyle(color: scheme.outline, fontSize: 13)),
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
        // 音訊被中斷(來電等):明確告知,並說明會自動恢復。
        if (state.interrupted)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Row(
              children: [
                Icon(Icons.phone_paused_rounded,
                    size: 15, color: scheme.tertiary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('錄音暫停中(來電或其他 App 佔用音訊)—— 結束後會自動繼續',
                      style: TextStyle(fontSize: 12, color: scheme.tertiary),
                      maxLines: 2),
                ),
              ],
            ),
          ),
        // 即時翻譯狀態(下載模型中 / 不可用),避免沒有譯文時使用者不知原因。
        if (state.translationStatus != TranslationStatus.off)
          _TranslationStatusBar(status: state.translationStatus),
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
              // 裝置內即時翻譯的雙語字幕(未開翻譯時為空 map)。
              translations: state.translations,
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
        FilterChip(
          label: const Text('翻譯'),
          avatar: const Icon(Icons.translate_rounded, size: 18),
          selected: settings.translationEnabled,
          onSelected: (v) async {
            await ref.read(settingsProvider.notifier).setTranslationEnabled(v);
            if (v) {
              // 先把模型備妥,避免開始錄音後前幾句還在下載而沒有譯文。
              ref.read(translationModelsProvider.notifier).ensureDownloaded(
                  [settings.translationSource, settings.translationTarget]);
            }
          },
        ),
        if (settings.translationEnabled)
          ActionChip(
            avatar: const Icon(Icons.swap_horiz_rounded, size: 18),
            label: Text('${translationLanguageLabel(settings.translationSource)}'
                ' → ${translationLanguageLabel(settings.translationTarget)}'),
            onPressed: () => _pickTranslationLanguages(context, ref, settings),
          ),
      ],
    );
  }

  /// 錄音前調整翻譯方向(先選來源、再選目標;選到相同會自動交換)。
  Future<void> _pickTranslationLanguages(
      BuildContext context, WidgetRef ref, Settings settings) async {
    final notifier = ref.read(settingsProvider.notifier);
    final source = await showLanguagePicker(context,
        title: '說話的語言', current: settings.translationSource);
    if (source == null || !context.mounted) return;
    await notifier.setTranslationLanguages(source: source);
    if (!context.mounted) return;
    final target = await showLanguagePicker(context,
        title: '翻譯成',
        current: ref.read(settingsProvider).translationTarget);
    if (target == null) return;
    await notifier.setTranslationLanguages(target: target);
    final s = ref.read(settingsProvider);
    await ref
        .read(translationModelsProvider.notifier)
        .ensureDownloaded([s.translationSource, s.translationTarget]);
  }

  Future<void> _pickSpeakerCount(
      BuildContext context, WidgetRef ref, Settings settings) async {
    final result = await showSpeakerCountPicker(context);
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

/// 即時(裝置內)翻譯狀態列。
///
/// 首次使用某語言要下載模型(約 30MB),期間不會有譯文;下載失敗也要讓使用者知道,
/// 否則只看到「沒有翻譯」卻不知原因。
class _TranslationStatusBar extends ConsumerWidget {
  const _TranslationStatusBar({required this.status});
  final TranslationStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final settings = ref.watch(settingsProvider);
    final direction =
        '${translationLanguageLabel(settings.translationSource)}'
        ' → ${translationLanguageLabel(settings.translationTarget)}';

    late final IconData icon;
    late final String text;
    late final Color color;
    switch (status) {
      case TranslationStatus.preparing:
        icon = Icons.cloud_download_outlined;
        text = '正在下載語言模型($direction)…約 30MB,完成後開始顯示譯文';
        color = scheme.primary;
      case TranslationStatus.ready:
        icon = Icons.translate_rounded;
        text = '即時翻譯:$direction';
        color = scheme.primary;
      case TranslationStatus.unavailable:
        icon = Icons.error_outline_rounded;
        text = '即時翻譯不可用($direction)—— 語言模型下載失敗,請確認網路後重新開始錄音';
        color = scheme.error;
      case TranslationStatus.off:
        return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Row(
        children: [
          if (status == TranslationStatus.preparing)
            SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          else
            Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 12, color: color),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}
