import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../core/utils/formatters.dart';
import '../../models/meeting.dart';
import '../../models/transcript_segment.dart';
import '../../providers/meetings_controller.dart';
import '../../providers/service_providers.dart';
import '../../services/export_service.dart';
import '../../widgets/audio_player_bar.dart';
import '../../widgets/export_button.dart';
import '../../widgets/transcript_view.dart';
import '../assistant/assistant_screen.dart';
import '../summary/summary_view.dart';

class MeetingDetailScreen extends ConsumerStatefulWidget {
  const MeetingDetailScreen({super.key, required this.meetingId});
  final String meetingId;

  @override
  ConsumerState<MeetingDetailScreen> createState() =>
      _MeetingDetailScreenState();
}

class _MeetingDetailScreenState extends ConsumerState<MeetingDetailScreen> {
  Timer? _poll;
  MeetingStatus? _prevStatus;

  String get meetingId => widget.meetingId;

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  /// 整檔上傳/處理中時每 3 秒輪詢會議狀態;完成(ready)後刷新逐字稿與摘要。
  void _syncPolling(MeetingStatus status) {
    final busy = status == MeetingStatus.uploading ||
        status == MeetingStatus.transcribing ||
        status == MeetingStatus.processing;
    if (busy) {
      _poll ??= Timer.periodic(const Duration(seconds: 3),
          (_) => ref.invalidate(meetingProvider(meetingId)));
    } else {
      _poll?.cancel();
      _poll = null;
      // 剛從處理中 → ready:把逐字稿重新拉一次(延後到 frame 後,避免在 build 期間改 provider)。
      if (_prevStatus != null && _prevStatus != status) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) ref.invalidate(transcriptProvider(meetingId));
        });
      }
    }
    _prevStatus = status;
  }

  @override
  Widget build(BuildContext context) {
    final meetingAsync = ref.watch(meetingProvider(meetingId));
    meetingAsync.whenData((m) => _syncPolling(m.status));

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            meetingAsync.maybeWhen(
                data: (m) => m.title, orElse: () => '會議'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            _DeleteAction(
              meetingId: meetingId,
              title: meetingAsync.maybeWhen(
                  data: (m) => m.title, orElse: () => '此會議'),
            ),
          ],
          bottom: TabBar(
            dividerColor: Colors.transparent,
            labelColor: Theme.of(context).colorScheme.primary,
            unselectedLabelColor: Theme.of(context).colorScheme.outline,
            labelStyle:
                const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            indicatorSize: TabBarIndicatorSize.label,
            indicator: UnderlineTabIndicator(
              borderRadius: BorderRadius.circular(3),
              borderSide: BorderSide(
                  width: 3, color: Theme.of(context).colorScheme.primary),
            ),
            tabs: const [
              Tab(text: '逐字稿'),
              Tab(text: '摘要'),
              Tab(text: '助理'),
            ],
          ),
        ),
        body: meetingAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('載入失敗:$e')),
          data: (meeting) => _Body(meeting: meeting),
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.meeting});
  final Meeting meeting;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localPath = ref.read(localRecordingStoreProvider).pathFor(meeting.id);
    final backend = ref.read(backendProvider);
    final remoteUri = meeting.remoteAudioUrl != null
        ? backend.resolveUri(meeting.remoteAudioUrl!)
        : null;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              Icon(Icons.calendar_today,
                  size: 14, color: Theme.of(context).colorScheme.outline),
              const SizedBox(width: 6),
              Text(Formatters.dateTime(meeting.createdAt),
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.outline,
                      fontSize: 13)),
              const Spacer(),
              _StatusChip(status: meeting.status),
            ],
          ),
        ),
        if (localPath != null || remoteUri != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: FutureBuilder<Map<String, String>>(
              future: backend.authHeaders(),
              builder: (context, snap) => AudioPlayerBar(
                localPath: localPath,
                remoteUri: remoteUri,
                headers: snap.data,
              ),
            ),
          ),
        const Divider(height: 1),
        Expanded(
          child: TabBarView(
            children: [
              _TranscriptTab(meeting: meeting),
              SummaryView(meeting: meeting),
              AssistantScreen(
                scope: meeting.id,
                embedded: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TranscriptTab extends ConsumerWidget {
  const _TranscriptTab({required this.meeting});
  final Meeting meeting;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transcript = ref.watch(transcriptProvider(meeting.id));
    return transcript.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('載入逐字稿失敗:$e')),
      data: (segments) {
        final busy = meeting.status == MeetingStatus.uploading ||
            meeting.status == MeetingStatus.transcribing ||
            meeting.status == MeetingStatus.processing;
        final view = RefreshIndicator(
          onRefresh: () async => ref.invalidate(transcriptProvider(meeting.id)),
          child: TranscriptView(
            segments: segments,
            emptyHint: busy ? '轉錄中,完成後會自動顯示…' : '這場會議還沒有逐字稿',
          ),
        );
        if (segments.isEmpty) return view;
        return Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: ExportButton(
                  label: '匯出逐字稿 .txt',
                  onExport: (origin) => _export(context, segments, origin),
                ),
              ),
            ),
            Expanded(child: view),
          ],
        );
      },
    );
  }

  Future<void> _export(
      BuildContext context, List<TranscriptSegment> segments, Rect? origin) async {
    try {
      await ExportService.exportTranscript(meeting, segments,
          shareOrigin: origin);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('匯出失敗:$e')));
      }
    }
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final MeetingStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ready = status == MeetingStatus.ready;
    final error = status == MeetingStatus.error;
    final color = error
        ? scheme.error
        : (ready ? scheme.primary : scheme.tertiary);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!ready && !error)
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: color),
            ),
          if (!ready && !error) const SizedBox(width: 6),
          Text(status.label,
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// 會議詳情頁的刪除按鈕:確認後呼叫 DELETE /meetings/{id}
/// (server 會連帶刪除逐字稿、摘要與 RAG 向量索引),成功後返回清單。
class _DeleteAction extends ConsumerStatefulWidget {
  const _DeleteAction({required this.meetingId, required this.title});
  final String meetingId;
  final String title;

  @override
  ConsumerState<_DeleteAction> createState() => _DeleteActionState();
}

class _DeleteActionState extends ConsumerState<_DeleteAction> {
  bool _deleting = false;

  Future<void> _confirmAndDelete() async {
    final scheme = Theme.of(context).colorScheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('刪除會議'),
        content: Text(
            '確定刪除「${widget.title}」?\n逐字稿、摘要與檢索索引都會從 server 一併刪除,無法復原。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.errorContainer,
              foregroundColor: scheme.onErrorContainer,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('刪除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      await ref
          .read(meetingsListProvider.notifier)
          .delete(widget.meetingId);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已刪除會議')));
      context.pop(); // 返回會議清單(清單已 invalidate,會自動移除)
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is ApiException ? e.message : '刪除失敗:$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_deleting) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 18),
        child: Center(
          child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }
    return IconButton(
      tooltip: '刪除會議',
      icon: const Icon(Icons.delete_outline_rounded),
      onPressed: _confirmAndDelete,
    );
  }
}
