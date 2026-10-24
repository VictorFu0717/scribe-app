import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/network/api_exception.dart';
import '../../core/utils/formatters.dart';
import '../../providers/recording_controller.dart';
import '../../providers/service_providers.dart';
import '../../providers/settings_controller.dart';
import '../../services/local_meeting_data.dart';
import '../../services/storage_cleanup.dart';
import '../../widgets/upload_progress_dialog.dart';

/// 清理錄音檔:找出會議已刪除、卻還留在手機上的錄音,由使用者確認後刪除。
///
/// 先前刪除會議只刪 server 的資料,錄音檔一直留在手機上,而且在 App 裡已經
/// 沒有入口能看到。
///
/// **不會自動刪**,一律列出來讓使用者勾選、確認。因為「在目前帳號的會議清單裡
/// 找不到」不一定代表會議已刪除 —— 這支手機若登入過別的帳號,那個帳號的錄音
/// 也會被列進來。
class StorageCleanupScreen extends ConsumerStatefulWidget {
  const StorageCleanupScreen({super.key});

  @override
  ConsumerState<StorageCleanupScreen> createState() =>
      _StorageCleanupScreenState();
}

class _StorageCleanupScreenState extends ConsumerState<StorageCleanupScreen> {
  bool _loading = true;
  bool _deleting = false;

  /// 不能清理的原因(此時不列任何檔案)。
  String? _blocked;
  bool _canRetry = false;

  StorageScan? _scan;
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _blocked = null;
      _canRetry = false;
    });

    String? blocked;
    var canRetry = false;
    StorageScan? scan;

    if (ref.read(settingsProvider).useMock) {
      blocked = '示範(Mock)模式下的會議清單是假資料,無法判斷哪些錄音已經沒有對應的會議。'
          '請先關閉 Mock 模式。';
    } else if (ref.read(recordingControllerProvider).isActive) {
      // 錄音中的檔案正在寫入,不能讓它出現在可刪除的清單裡
      blocked = '正在錄音,請結束錄音後再清理。';
    } else {
      try {
        // 一定要拿到**完整**的會議清單才能判斷;拿不到就不清理,
        // 否則還在的會議會被當成已刪除。
        final meetings = await ref.read(backendProvider).listMeetings();
        final files = ref.read(localRecordingStoreProvider).allFiles();
        scan = analyzeLocalAudio(files, {for (final m in meetings) m.id});
      } catch (e) {
        final why = e is ApiException ? e.message : '$e';
        blocked = '無法取得會議清單($why)。為避免誤刪還在的會議的錄音,暫時不能清理。';
        canRetry = true;
      }
    }

    if (!mounted) return;
    setState(() {
      _loading = false;
      _blocked = blocked;
      _canRetry = canRetry;
      _scan = scan;
      _selected
        ..clear()
        ..addAll([for (final f in scan?.removable ?? const []) f.file.path]);
    });
  }

  List<LocalAudioFile> get _selectedFiles => [
        for (final f in _scan?.removable ?? const <LocalAudioFile>[])
          if (_selected.contains(f.file.path)) f,
      ];

  Future<void> _deleteSelected() async {
    final files = _selectedFiles;
    if (files.isEmpty) return;
    final bytes = files.fold<int>(0, (n, f) => n + f.size);
    final scheme = Theme.of(context).colorScheme;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('刪除錄音檔'),
        content: Text('確定刪除 ${files.length} 個檔案(共 '
            '${UploadProgressDialog.formatBytes(bytes)})?刪除後無法復原。'),
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
    var deleted = 0;
    var freed = 0;
    final orphanIds = {for (final f in _scan!.orphans) f.meetingId};
    for (final f in files) {
      try {
        await f.file.delete();
        deleted++;
        freed += f.size;
      } catch (_) {}
    }
    // 已刪除會議的檔案全刪光了,就把它殘留的本機記錄一起清掉
    final store = ref.read(localRecordingStoreProvider);
    final remaining = {for (final f in store.allFiles()) f.meetingId};
    for (final id in orphanIds.difference(remaining)) {
      await forgetLocalMeetingRecords(ref.read, id);
    }

    if (!mounted) return;
    setState(() => _deleting = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(deleted == files.length
          ? '已刪除 $deleted 個檔案,釋放 ${UploadProgressDialog.formatBytes(freed)}'
          : '已刪除 $deleted 個檔案,有 ${files.length - deleted} 個刪不掉'),
    ));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final scan = _scan;
    final selected = _selectedFiles;
    final selectedBytes = selected.fold<int>(0, (n, f) => n + f.size);

    return Scaffold(
      appBar: AppBar(title: const Text('清理錄音檔')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _blocked != null
              ? _BlockedView(
                  message: _blocked!, onRetry: _canRetry ? _load : null)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 110),
                    children: [
                      _SummaryCard(scan: scan!),
                      if (scan.orphans.isNotEmpty) ...[
                        _sectionHeader('找不到對應會議(${scan.orphans.length})'),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                          child: Text(
                            '這些錄音在目前帳號的會議清單裡找不到,多半是會議已經刪除了。'
                            '若這支手機曾登入其他帳號,那個帳號的錄音也會出現在這裡。'
                            '不確定的話,可以按右邊的分享按鈕先存出來。',
                            style: TextStyle(
                                fontSize: 12.5,
                                height: 1.45,
                                color: scheme.onSurfaceVariant),
                          ),
                        ),
                        for (final f in scan.orphans) _fileTile(f),
                      ],
                      if (scan.empty.isNotEmpty) ...[
                        _sectionHeader('沒有內容的壞檔(${scan.empty.length})'),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                          child: Text(
                            '0 位元組的檔案,是早期壓縮失敗時留下的,沒有任何聲音。'
                            '會議原本的錄音不受影響。',
                            style: TextStyle(
                                fontSize: 12.5,
                                height: 1.45,
                                color: scheme.onSurfaceVariant),
                          ),
                        ),
                        for (final f in scan.empty) _fileTile(f),
                      ],
                    ],
                  ),
                ),
      bottomNavigationBar: scan == null || scan.removable.isEmpty
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError,
                ),
                onPressed:
                    selected.isEmpty || _deleting ? null : _deleteSelected,
                icon: _deleting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.delete_outline_rounded),
                label: Text(selected.isEmpty
                    ? '請勾選要刪除的檔案'
                    : '刪除所選(${selected.length} 個,'
                        '${UploadProgressDialog.formatBytes(selectedBytes)})'),
              ),
            ),
    );
  }

  Widget _sectionHeader(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
        child: Text(text,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.primary)),
      );

  Widget _fileTile(LocalAudioFile f) {
    final length = estimateRecordingLength(f);
    final parts = [
      UploadProgressDialog.formatBytes(f.size),
      if (length != null) '約 ${_formatLength(length)}',
      f.imported ? '匯入的音檔' : 'App 錄音',
    ];
    final name = f.file.path.substring(f.file.path.lastIndexOf('/') + 1);
    return CheckboxListTile(
      value: _selected.contains(f.file.path),
      onChanged: _deleting
          ? null
          : (v) => setState(() => v == true
              ? _selected.add(f.file.path)
              : _selected.remove(f.file.path)),
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(Formatters.dateTime(f.modified)),
      subtitle: Text('${parts.join(' · ')}\n$name',
          style: const TextStyle(fontSize: 12)),
      isThreeLine: true,
      secondary: f.size == 0
          ? null
          : Builder(
              builder: (btnContext) => IconButton(
                tooltip: '先存出來',
                icon: const Icon(Icons.ios_share_rounded),
                onPressed: () => _share(btnContext, f),
              ),
            ),
    );
  }

  Future<void> _share(BuildContext btnContext, LocalAudioFile f) async {
    final box = btnContext.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(ShareParams(
      files: [XFile(f.file.path)],
      // iPad 的分享面板需要錨點
      sharePositionOrigin: box == null || !box.hasSize
          ? null
          : box.localToGlobal(Offset.zero) & box.size,
    ));
  }

  static String _formatLength(Duration d) {
    if (d.inHours > 0) return '${d.inHours} 小時 ${d.inMinutes % 60} 分';
    if (d.inMinutes > 0) return '${d.inMinutes} 分鐘';
    return '${d.inSeconds} 秒';
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.scan});

  final StorageScan scan;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final removable = scan.removable;
    final removableBytes = removable.fold<int>(0, (n, f) => n + f.size);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('手機上的錄音',
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text(
              '${scan.all.length} 個 · '
              '${UploadProgressDialog.formatBytes(scan.totalBytes)}',
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                removable.isEmpty
                    ? Icons.check_circle_rounded
                    : Icons.cleaning_services_outlined,
                size: 18,
                color: removable.isEmpty ? Colors.green : scheme.error,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  removable.isEmpty
                      ? '沒有需要清理的檔案,每個錄音都有對應的會議。'
                      : '可清理 ${removable.length} 個,'
                          '共 ${UploadProgressDialog.formatBytes(removableBytes)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BlockedView extends StatelessWidget {
  const _BlockedView({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shield_outlined, size: 44, color: scheme.outline),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(height: 1.5)),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonal(onPressed: onRetry, child: const Text('重試')),
            ],
          ],
        ),
      ),
    );
  }
}
