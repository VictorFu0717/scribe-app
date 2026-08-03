import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_style.dart';
import '../../core/utils/formatters.dart';
import '../../models/meeting.dart';
import '../../providers/auth_controller.dart';
import '../../providers/meetings_controller.dart';
import '../../providers/service_providers.dart';
import '../../routing/app_router.dart';
import '../../widgets/brand_wave.dart';
import '../../widgets/soft_card.dart';

class MeetingsListScreen extends ConsumerWidget {
  const MeetingsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meetings = ref.watch(meetingsListProvider);

    return Scaffold(
      floatingActionButton: _RecordFab(onTap: () => context.push(Routes.record)),
      body: RefreshIndicator(
        onRefresh: () => ref.read(meetingsListProvider.notifier).refresh(),
        child: CustomScrollView(
          slivers: [
            SliverAppBar.large(
              title: const Text('會議'),
              actions: [
                IconButton(
                  tooltip: '上傳音檔',
                  icon: const Icon(Icons.upload_file_outlined),
                  onPressed: () => _importAudio(context, ref),
                ),
                IconButton(
                  tooltip: '個人助理',
                  icon: const Icon(Icons.auto_awesome_outlined),
                  onPressed: () => context.push(Routes.assistant),
                ),
                IconButton(
                  tooltip: '設定',
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () => context.push(Routes.settings),
                ),
                IconButton(
                  tooltip: '登出',
                  icon: const Icon(Icons.logout_rounded),
                  onPressed: () =>
                      ref.read(authControllerProvider.notifier).logout(),
                ),
                const SizedBox(width: 4),
              ],
            ),
            meetings.when(
              loading: () => const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator())),
              error: (e, _) => SliverFillRemaining(
                hasScrollBody: false,
                child: _ErrorView(
                  message: '$e',
                  onRetry: () =>
                      ref.read(meetingsListProvider.notifier).refresh(),
                ),
              ),
              data: (list) {
                if (list.isEmpty) {
                  return const SliverFillRemaining(
                      hasScrollBody: false, child: _EmptyView());
                }
                return SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
                  sliver: SliverList.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => _MeetingCard(
                      meeting: list[i],
                      onTap: () => context.push(Routes.meeting(list[i].id)),
                      onDelete: () =>
                          ref.read(meetingsListProvider.notifier).delete(list[i].id),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 匯入手機上現有的音檔 → 建會議 → 上傳給 server 背景轉錄 → 進詳情頁(會輪詢)。
  Future<void> _importAudio(BuildContext context, WidgetRef ref) async {
    FilePickerResult? picked;
    try {
      // 用文件選取器(Files)挑音檔,而非 FileType.audio 的音樂庫選取器
      // (後者在 iOS 需 NSAppleMusicUsageDescription,否則閃退,且是選歌不是選檔)。
      picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const [
          'wav', 'm4a', 'mp3', 'aac', 'aiff', 'caf', 'flac'
        ],
      );
    } catch (e) {
      if (context.mounted) _toast(context, '選取檔案失敗:$e');
      return;
    }
    final path = picked?.files.single.path;
    if (path == null) return; // 使用者取消

    final rawName = picked!.files.single.name;
    final dot = rawName.lastIndexOf('.');
    final title = dot > 0 ? rawName.substring(0, dot) : rawName;

    if (context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const _UploadingDialog(),
      );
    }
    try {
      final backend = ref.read(backendProvider);
      final config = ref.read(transcriptionConfigProvider);
      final meeting = await backend.createMeeting(title: title);
      await backend.uploadAudio(meeting.id, path, config: config);
      ref.invalidate(meetingsListProvider);
      if (context.mounted) {
        Navigator.of(context).pop(); // 關閉上傳中對話框
        context.push(Routes.meeting(meeting.id));
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
        _toast(context, e is ApiException ? e.message : '上傳失敗:$e');
      }
    }
  }

  void _toast(BuildContext context, String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

class _UploadingDialog extends StatelessWidget {
  const _UploadingDialog();
  @override
  Widget build(BuildContext context) {
    return const AlertDialog(
      content: Row(
        children: [
          SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5)),
          SizedBox(width: 16),
          Expanded(child: Text('上傳中…')),
        ],
      ),
    );
  }
}

class _RecordFab extends StatelessWidget {
  const _RecordFab({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppStyle.rXl),
        gradient: AppGradients.record,
        boxShadow: AppShadows.glow(const Color(0xFFEF4444), strength: 0.45),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppStyle.rXl),
          onTap: onTap,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 22, vertical: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.mic_rounded, color: Colors.white),
                SizedBox(width: 8),
                Text('開始錄音',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MeetingCard extends StatelessWidget {
  const _MeetingCard(
      {required this.meeting, required this.onTap, required this.onDelete});

  final Meeting meeting;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dismissible(
      key: ValueKey(meeting.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(AppStyle.rLg),
        ),
        child: Icon(Icons.delete_outline_rounded, color: scheme.error),
      ),
      confirmDismiss: (_) => _confirm(context),
      onDismissed: (_) => onDelete(),
      child: SoftCard(
        onTap: onTap,
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            _GradientAvatar(seed: meeting.title),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(meeting.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontSize: 16)),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Icon(Icons.schedule_rounded,
                          size: 13, color: scheme.outline),
                      const SizedBox(width: 4),
                      Text(Formatters.relativeDay(meeting.createdAt),
                          style:
                              TextStyle(color: scheme.outline, fontSize: 13)),
                      Text('  ·  ${Formatters.durationSeconds(meeting.durationSec)}',
                          style:
                              TextStyle(color: scheme.outline, fontSize: 13)),
                    ],
                  ),
                ],
              ),
            ),
            if (meeting.hasSummary)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  gradient: AppGradients.accent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.auto_awesome,
                    size: 13, color: Colors.white),
              ),
            Icon(Icons.chevron_right_rounded, color: scheme.outlineVariant),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirm(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('刪除會議'),
        content: Text(
            '確定刪除「${meeting.title}」?\n逐字稿、摘要與檢索索引都會從 server 一併刪除,無法復原。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton.tonal(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('刪除')),
        ],
      ),
    );
    return ok ?? false;
  }
}

class _GradientAvatar extends StatelessWidget {
  const _GradientAvatar({required this.seed});
  final String seed;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        gradient: AppGradients.forSeed(seed),
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppShadows.glow(AppGradients.forSeed(seed).colors.last,
            strength: 0.25),
      ),
      child: const Icon(Icons.graphic_eq_rounded, color: Colors.white),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrandWave(size: 64),
            const SizedBox(height: 24),
            Text('尚無會議紀錄',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text('點右下角開始你的第一場錄音',
                style: TextStyle(color: scheme.outline)),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 56),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: onRetry, child: const Text('重試')),
          ],
        ),
      ),
    );
  }
}
