import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../core/utils/formatters.dart';
import '../../models/meeting.dart';
import '../../models/transcript_segment.dart';
import '../../providers/meetings_controller.dart';
import '../../providers/service_providers.dart';
import '../../providers/meeting_translation_controller.dart';
import '../../providers/transcript_translation_controller.dart';
import '../../providers/speaker_names_controller.dart';
import '../../providers/transcript_edits_controller.dart';
import '../../providers/upload_progress_controller.dart';
import '../../services/on_device_translator.dart';
import '../../widgets/language_picker.dart';
import '../../services/audio_convert.dart';
import '../../services/background_task.dart';
import '../../services/speaker_name_store.dart';
import '../../services/transcript_edit_store.dart';
import '../../services/save_to_device.dart';
import '../../services/export_service.dart';
import '../../widgets/audio_player_bar.dart';
import '../../widgets/export_button.dart';
import '../../widgets/transcript_view.dart';
import '../../widgets/segment_edit_sheet.dart';
import '../../widgets/speaker_edit_sheet.dart';
import '../../widgets/upload_progress_dialog.dart';
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
          if (!mounted) return;
          ref.invalidate(rawTranscriptProvider(meetingId));
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
            tabs: [
              const Tab(text: '逐字稿'),
              const Tab(text: '摘要'),
              const Tab(text: '助理'),
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
    // 只有手機錄下、沙盒裡實際存在的檔案才可分享(匯入的檔在 server、使用者本機已有)。
    final canShareAudio = localPath != null && File(localPath).existsSync();

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
            child: Row(
              children: [
                Expanded(
                  child: FutureBuilder<Map<String, String>>(
                    future: backend.authHeaders(),
                    builder: (context, snap) => AudioPlayerBar(
                      meetingId: meeting.id,
                      localPath: localPath,
                      remoteUri: remoteUri,
                      headers: snap.data,
                    ),
                  ),
                ),
                if (canShareAudio) ...[
                  const SizedBox(width: 4),
                  // Android 的分享選單沒有「儲存到檔案」,另給一個存到手機的按鈕。
                  if (SaveToDevice.isSupported)
                    _SaveAudioButton(meeting: meeting, audioPath: localPath),
                  _ShareAudioButton(meeting: meeting, audioPath: localPath),
                ],
              ],
            ),
          ),
        if (localPath == null && remoteUri == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                Icon(Icons.music_off_outlined,
                    size: 14, color: Theme.of(context).colorScheme.outline),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('這場會議在本機沒有錄音檔可播放',
                      style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.outline)),
                ),
              ],
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
    // 有錄音可播,時間戳才做成可點(否則顯示為灰色不可點,避免點了沒反應)。
    final localPath = ref.read(localRecordingStoreProvider).pathFor(meeting.id);
    final hasAudio = (localPath != null && File(localPath).existsSync()) ||
        meeting.remoteAudioUrl != null;
    // 翻譯是**這場會議自己的**設定(預設關閉),不再由全域開關決定。
    final pref = ref.watch(meetingTranslationProvider(meeting.id));
    final translations = pref.enabled
        ? ref.watch(transcriptTranslationProvider(meeting.id))
        : const <String, String>{};

    return transcript.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('載入逐字稿失敗:$e')),
      data: (segments) {
        final busy = meeting.status == MeetingStatus.uploading ||
            meeting.status == MeetingStatus.transcribing ||
            meeting.status == MeetingStatus.processing;
        // 轉錄中且尚無逐字稿:顯示明確的處理中狀態 + 手動重新整理(避免「一直轉錄中」)。
        if (segments.isEmpty && busy) {
          return _TranscribingPlaceholder(
            onRefresh: () {
              ref.invalidate(meetingProvider(meeting.id));
              ref.invalidate(rawTranscriptProvider(meeting.id));
            },
          );
        }

        // 這場會議有開翻譯才在背景補譯文(內部去重,重複呼叫安全)。
        if (pref.enabled && segments.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ref
                .read(transcriptTranslationProvider(meeting.id).notifier)
                .ensureTranslated(segments);
          });
        }

        // 沒有逐字稿但本機有音檔 → 上傳/轉錄曾失敗。提供重試,不必重新選檔。
        if (segments.isEmpty && !busy && localPath != null) {
          return _RetranscribeView(meeting: meeting, audioPath: localPath);
        }

        // 哪幾段被改過(用來標示「已編輯」)。
        final edits = ref.watch(transcriptEditsProvider(meeting.id));
        final editedKeys = <int>{};
        for (var i = 0; i < segments.length; i++) {
          if (edits.containsKey(
              TranscriptEditStore.keyFor(segments[i], i))) {
            editedKeys.add(i);
          }
        }

        final view = RefreshIndicator(
          onRefresh: () async => ref.invalidate(transcriptProvider(meeting.id)),
          child: TranscriptView(
            segments: segments,
            emptyHint: '這場會議還沒有逐字稿',
            translations: translations,
            editedKeys: editedKeys,
            // 點說話者名稱 → 改名(整場)或改成別人(這一段)。
            onEditSpeaker: (_, index) =>
                _editSpeaker(context, ref, meeting.id, index),
            // 點文字 → 修改該段(辨識有誤時自行改正)。
            onEdit: (segment, index) => _editSegment(
              context,
              ref,
              meeting.id,
              segment,
              index,
              canPlay: hasAudio,
            ),
            // 點時間戳跳到錄音的該位置並播放 —— 辨識有誤時可直接回去對照原音。
            //
            // 只在「這場會議的音源確實已載入」時才可點:播放器是 App 層級共用的
            // singleton,若這場沒有錄音檔(例如上傳的音檔 server 未留存),裡面還留著
            // 上一場的音源,無條件 seek 會播出**別場**會議的錄音(實測發生過)。
            onSeek: !hasAudio
                ? null
                : (position) async {
                    final player = ref.read(audioPlayerProvider);
                    // 再確認一次載入的是本場 —— 音源載入是非同步的。
                    if (player.loadedMeetingId != meeting.id) return;
                    await player.seek(position);
                    await player.play();
                  },
          ),
        );
        if (segments.isEmpty) return view;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  // 每場會議自己的翻譯開關與語言(預設關閉)。
                  Expanded(
                      child: _MeetingTranslationControls(
                          meetingId: meeting.id, pref: pref)),
                  const SizedBox(width: 8),
                  ExportButton(
                    label: '匯出逐字稿 .txt',
                    onExport: (origin) => _export(context, segments, origin,
                        translations: translations, pref: pref),
                  ),
                ],
              ),
            ),
            Expanded(child: view),
          ],
        );
      },
    );
  }

  /// 開啟編輯面板修改某一段逐字稿。
  ///
  /// 修訂存在本機(server 沒有修改逐字稿的端點),`transcriptProvider` 讀取時會
  /// 疊上去,所以畫面與匯出都會跟著變。
  Future<void> _editSegment(
    BuildContext context,
    WidgetRef ref,
    String meetingId,
    TranscriptSegment segment,
    int index, {
    required bool canPlay,
  }) async {
    final notifier = ref.read(transcriptEditsProvider(meetingId).notifier);
    final existing = notifier.editFor(segment, index);
    final startMs = segment.startMs;

    final result = await showModalBottomSheet<SegmentEditResult>(
      context: context,
      isScrollControlled: true, // 鍵盤升起時要能上推
      builder: (_) => SegmentEditSheet(
        text: segment.text,
        // 原文取自修訂記錄,沒改過就是目前的文字。
        original: existing?.original ?? segment.text,
        stamp: startMs == null
            ? null
            : Formatters.duration(Duration(milliseconds: startMs)),
        onPlay: !canPlay || startMs == null
            ? null
            : () async {
                final player = ref.read(audioPlayerProvider);
                // 播放器是 App 層級共用的,先確認載入的是本場會議。
                if (player.loadedMeetingId != meetingId) return;
                await player.seek(Duration(milliseconds: startMs));
                await player.play();
              },
      ),
    );
    if (result == null) return; // 取消

    if (result.revert) {
      await notifier.revert(segment, index);
    } else {
      await notifier.edit(segment, index, result.text);
    }
    // 不要 invalidate:transcriptProvider 已經 watch 修訂,會自己重算。
    // 重抓逐字稿只會讓畫面閃一下並把捲動位置歸零(見 transcriptProvider 的說明)。
  }

  /// 開啟說話者面板:改名(套用整場)或把這一段指派給別人。
  ///
  /// 傳的是 index 而非畫面上的片段 —— 指派必須拿 **server 原始的**片段來比對
  /// 原始說話者,畫面上的已經疊過設定了(名字可能已被改掉)。
  Future<void> _editSpeaker(
    BuildContext context,
    WidgetRef ref,
    String meetingId,
    int index,
  ) async {
    final rawSegments =
        ref.read(rawTranscriptProvider(meetingId)).valueOrNull;
    if (rawSegments == null || index >= rawSegments.length) return;

    final prefs = ref.read(speakerPrefsProvider(meetingId));
    // 清單 = server 原始標籤(依出現順序)+ 使用者自建的說話者。
    final canonical = <String>[];
    for (final seg in rawSegments) {
      final s = seg.speaker;
      if (s != null && s.isNotEmpty && !canonical.contains(s)) {
        canonical.add(s);
      }
    }
    for (final key in prefs.names.keys) {
      if (key.startsWith(SpeakerNameStore.customPrefix) &&
          !canonical.contains(key)) {
        canonical.add(key);
      }
    }
    if (canonical.isEmpty) return; // 沒開 diarization,沒有說話者可改

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SpeakerEditSheet(
        meetingId: meetingId,
        rawSegment: rawSegments[index],
        index: index,
        canonicalSpeakers: canonical,
      ),
    );
  }

  /// 匯出時一併帶上目前顯示的譯文,讓 .txt 與畫面上看到的雙語一致。
  Future<void> _export(
    BuildContext context,
    List<TranscriptSegment> segments,
    Rect? origin, {
    required Map<String, String> translations,
    required MeetingTranslationPref pref,
  }) async {
    try {
      await ExportService.exportTranscript(
        meeting,
        segments,
        shareOrigin: origin,
        translations: pref.enabled ? translations : const {},
        translationNote: pref.enabled && translations.isNotEmpty
            ? '${translationLanguageLabel(pref.source)}'
                ' → ${translationLanguageLabel(pref.target)}'
            : null,
      );
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

/// 轉錄處理中的佔位畫面(含手動重新整理),避免使用者卡在「一直轉錄中」不知能做什麼。
class _TranscribingPlaceholder extends StatelessWidget {
  const _TranscribingPlaceholder({required this.onRefresh});
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 3)),
            const SizedBox(height: 20),
            const Text('轉錄中,完成後會自動顯示…',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text('長會議需要一些時間;若等太久可手動重新整理。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: scheme.outline)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('重新整理'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 單一會議的翻譯控制:開關 + 語言方向。
///
/// 刻意做成「每場會議」而非全域:多數會議不需要翻譯,而各場語言也不同 ——
/// 用一個全域方向去翻所有會議,語言不符時會翻出垃圾(英文會議套「中→英」會原樣吐回)。
class _MeetingTranslationControls extends ConsumerWidget {
  const _MeetingTranslationControls({
    required this.meetingId,
    required this.pref,
  });
  final String meetingId;
  final MeetingTranslationPref pref;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(meetingTranslationProvider(meetingId).notifier);
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FilterChip(
          label: const Text('翻譯'),
          avatar: const Icon(Icons.translate_rounded, size: 18),
          selected: pref.enabled,
          onSelected: notifier.setEnabled,
          visualDensity: VisualDensity.compact,
        ),
        if (pref.enabled)
          ActionChip(
            avatar: const Icon(Icons.swap_horiz_rounded, size: 18),
            label: Text('${translationLanguageLabel(pref.source)}'
                ' → ${translationLanguageLabel(pref.target)}'),
            visualDensity: VisualDensity.compact,
            onPressed: () => _pickLanguages(context, notifier),
          ),
      ],
    );
  }

  Future<void> _pickLanguages(
      BuildContext context, MeetingTranslationController notifier) async {
    final source = await showLanguagePicker(context,
        title: '這場會議的語言', current: pref.source);
    if (source == null || !context.mounted) return;
    await notifier.setLanguages(source: source);
    if (!context.mounted) return;
    final target = await showLanguagePicker(context,
        title: '翻譯成', current: pref.target == source ? pref.source : pref.target);
    if (target == null) return;
    await notifier.setLanguages(target: target);
  }
}

/// 分享本地錄音檔:叫出系統分享面板(存到「檔案」、AirDrop、其他 App…)。
/// 點擊時把自身位置當 iPad 分享面板錨點傳給 ExportService。
class _ShareAudioButton extends ConsumerStatefulWidget {
  const _ShareAudioButton({required this.meeting, required this.audioPath});
  final Meeting meeting;
  final String audioPath;

  @override
  ConsumerState<_ShareAudioButton> createState() => _ShareAudioButtonState();
}

class _ShareAudioButtonState extends ConsumerState<_ShareAudioButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: '分享錄音檔',
      icon: _busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.5))
          : const Icon(Icons.ios_share),
      onPressed: _busy ? null : _share,
    );
  }

  Future<void> _share() async {
    final box = context.findRenderObject() as RenderBox?;
    final origin = (box != null && box.hasSize)
        ? box.localToGlobal(Offset.zero) & box.size
        : null;

    var path = widget.audioPath;
    setState(() => _busy = true);
    try {
      // WAV 太大送不出去(一小時約 110MB,實測 LINE 無法傳送)→ 先壓成 m4a(約 8MB)。
      // 轉檔成功就更新本機記錄並刪掉 WAV,之後播放/分享都用小檔,也省下手機空間。
      //
      // 壓縮就是在這裡(以及「存到手機」)才做的 —— 錄音停止時刻意不壓縮,
      // 以免拖累收尾流程(見 RecordingController.stop 的說明),所以這裡會遇到
      // 尚未壓縮的新錄音,不只是舊檔。
      if (await AudioConvert.isWav(path)) {
        final converted = await AudioConvert.wavToM4a(path);
        if (converted != null) {
          path = converted;
          await ref
              .read(localRecordingStoreProvider)
              .save(widget.meeting.id, converted);
        } else if (mounted) {
          // 不要靜默 —— 先前壓縮一直失敗卻照樣傳原檔,看起來像功能沒作用。
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('壓縮失敗,將傳送原始檔案(檔案較大)')));
        }
      }
      await ExportService.exportAudio(widget.meeting, path,
          shareOrigin: origin);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('分享失敗:$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// 有本機錄音卻沒有逐字稿時的補救畫面(上傳或轉錄曾中斷)。
///
/// 直接用本機那份音檔重新送去轉錄,使用者不必重新選檔,也不會失去這場會議。
class _RetranscribeView extends ConsumerStatefulWidget {
  const _RetranscribeView({required this.meeting, required this.audioPath});
  final Meeting meeting;
  final String audioPath;

  @override
  ConsumerState<_RetranscribeView> createState() => _RetranscribeViewState();
}

class _RetranscribeViewState extends ConsumerState<_RetranscribeView> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_upload_outlined, size: 34, color: scheme.outline),
            const SizedBox(height: 14),
            const Text('這場會議還沒有逐字稿',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text('錄音檔已存在手機上,可以重新送去轉錄。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: scheme.outline)),
            const SizedBox(height: 18),
            if (_busy)
              const Column(children: [
                SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 3)),
                SizedBox(height: 10),
                Text('上傳中…請暫時不要切換到其他 App',
                    style: TextStyle(fontSize: 12.5)),
              ])
            else
              FilledButton.icon(
                onPressed: _retranscribe,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('重新轉錄'),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _retranscribe() async {
    setState(() => _busy = true);
    final progress = ref.read(uploadProgressProvider.notifier);
    progress.begin(UploadPhase.uploading);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const UploadProgressDialog(),
    );
    try {
      await BackgroundTask.run(() => ref.read(backendProvider).uploadAudio(
            widget.meeting.id,
            widget.audioPath,
            config: ref.read(transcriptionConfigProvider),
            onProgress: progress.onBytes,
          ));
      if (!mounted) return;
      Navigator.of(context).pop(); // 關閉進度對話框
      // 重新拉狀態與逐字稿(server 會轉為處理中,詳情頁本身會輪詢)。
      ref.invalidate(meetingProvider(widget.meeting.id));
      ref.invalidate(rawTranscriptProvider(widget.meeting.id));
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text(e is ApiException ? e.message : '重新轉錄失敗:$e')));
      }
    } finally {
      progress.reset();
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// 把錄音檔存到手機(Android)。
///
/// iOS 不顯示此按鈕 —— 其分享面板已內建「儲存到檔案」;Android 的分享選單只列
/// 可接收檔案的 App,沒有存檔選項,故需另走 SAF 的「另存新檔」。
class _SaveAudioButton extends ConsumerStatefulWidget {
  const _SaveAudioButton({required this.meeting, required this.audioPath});
  final Meeting meeting;
  final String audioPath;

  @override
  ConsumerState<_SaveAudioButton> createState() => _SaveAudioButtonState();
}

class _SaveAudioButtonState extends ConsumerState<_SaveAudioButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: '存到手機',
      icon: _busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.5))
          : const Icon(Icons.download_rounded),
      onPressed: _busy ? null : _save,
    );
  }

  Future<void> _save() async {
    var path = widget.audioPath;
    setState(() => _busy = true);
    try {
      // 與分享一致:WAV 太大(一小時約 110MB)先壓成 m4a,並更新本機記錄。
      if (await AudioConvert.isWav(path)) {
        final converted = await AudioConvert.wavToM4a(path);
        if (converted != null) {
          path = converted;
          await ref
              .read(localRecordingStoreProvider)
              .save(widget.meeting.id, converted);
        }
      }
      final ok = await SaveToDevice.save(
        path,
        fileName: ExportService.audioFileName(widget.meeting, path),
        mimeType: ExportService.audioMimeType(path),
      );
      if (mounted && ok) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已存到手機')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('存檔失敗:$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
