import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_style.dart';
import '../../models/summary.dart';
import '../../providers/summary_controller.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/soft_card.dart';

/// 會議摘要分頁。支援 SSE 串流即時顯示 + 結構化區塊。
class SummaryView extends ConsumerWidget {
  const SummaryView({super.key, required this.meetingId});
  final String meetingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(summaryControllerProvider(meetingId));
    final notifier = ref.read(summaryControllerProvider(meetingId).notifier);

    if (state.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!state.hasContent && !state.streaming) {
      return _GenerateCta(error: state.error, onGenerate: notifier.generate);
    }

    final summary = state.summary;
    return RefreshIndicator(
      onRefresh: notifier.generate,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          if (state.streaming) const _StreamingBanner(),
          if (summary != null && !summary.isEmpty)
            ..._structured(context, summary)
          else if (state.streamingText.isNotEmpty)
            SoftCard(
              child: Text(state.streamingText,
                  style: const TextStyle(fontSize: 15, height: 1.6)),
            ),
          const SizedBox(height: 20),
          if (!state.streaming)
            OutlinedButton.icon(
              onPressed: notifier.generate,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重新產生摘要'),
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppStyle.rMd))),
            ),
        ],
      ),
    );
  }

  List<Widget> _structured(BuildContext context, MeetingSummary s) {
    return [
      if (s.overview.isNotEmpty)
        _Section(
          icon: Icons.notes_rounded,
          title: '會議摘要',
          color: const Color(0xFF6366F1),
          child: Text(s.overview,
              style: const TextStyle(fontSize: 15, height: 1.65)),
        ),
      if (s.keyPoints.isNotEmpty)
        _Section(
          icon: Icons.lightbulb_outline_rounded,
          title: '討論重點',
          color: const Color(0xFFF59E0B),
          child: _BulletList(items: s.keyPoints, color: const Color(0xFFF59E0B)),
        ),
      if (s.decisions.isNotEmpty)
        _Section(
          icon: Icons.gavel_rounded,
          title: '決議事項',
          color: const Color(0xFF10B981),
          child: _BulletList(items: s.decisions, color: const Color(0xFF10B981)),
        ),
      if (s.actionItems.isNotEmpty)
        _Section(
          icon: Icons.checklist_rtl_rounded,
          title: '待辦事項',
          color: const Color(0xFF3B82F6),
          child: Column(
            children:
                s.actionItems.map((a) => _ActionItemTile(item: a)).toList(),
          ),
        ),
      if (s.followUps.isNotEmpty)
        _Section(
          icon: Icons.event_repeat_rounded,
          title: '後續追蹤',
          color: const Color(0xFFEC4899),
          child: _BulletList(items: s.followUps, color: const Color(0xFFEC4899)),
        ),
    ];
  }
}

class _StreamingBanner extends StatelessWidget {
  const _StreamingBanner();
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: AppGradients.accent,
        borderRadius: BorderRadius.circular(AppStyle.rMd),
      ),
      child: Row(
        children: const [
          SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white)),
          SizedBox(width: 10),
          Text('AI 產生摘要中…',
              style: TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.color,
    required this.child,
  });
  final IconData icon;
  final String title;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SoftCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 17, color: color),
                ),
                const SizedBox(width: 10),
                Text(title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _BulletList extends StatelessWidget {
  const _BulletList({required this.items, required this.color});
  final List<String> items;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items
          .map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 7, right: 10),
                      width: 6,
                      height: 6,
                      decoration:
                          BoxDecoration(color: color, shape: BoxShape.circle),
                    ),
                    Expanded(
                        child: Text(t,
                            style:
                                const TextStyle(fontSize: 15, height: 1.55))),
                  ],
                ),
              ))
          .toList(),
    );
  }
}

class _ActionItemTile extends StatelessWidget {
  const _ActionItemTile({required this.item});
  final ActionItem item;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(AppStyle.rMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.radio_button_unchecked_rounded,
              size: 20, color: scheme.outline),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.task,
                    style: const TextStyle(fontSize: 15, height: 1.4)),
                if (item.owner != null || item.due != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(
                      spacing: 8,
                      children: [
                        if (item.owner != null)
                          _MetaChip(
                              icon: Icons.person_outline_rounded,
                              text: item.owner!),
                        if (item.due != null)
                          _MetaChip(
                              icon: Icons.schedule_rounded, text: item.due!),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: scheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(text,
              style: TextStyle(
                  fontSize: 12.5, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _GenerateCta extends StatelessWidget {
  const _GenerateCta({this.error, required this.onGenerate});
  final String? error;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: AppGradients.accent,
                shape: BoxShape.circle,
                boxShadow: AppShadows.glow(AppGradients.accent.colors.last,
                    strength: 0.4),
              ),
              child:
                  const Icon(Icons.auto_awesome, size: 36, color: Colors.white),
            ),
            const SizedBox(height: 20),
            Text('尚未產生摘要',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text('產生會議摘要、討論重點、決議與待辦事項',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.outline)),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.error)),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: 220,
              child: GradientButton(
                label: '產生摘要',
                icon: Icons.auto_awesome,
                gradient: AppGradients.accent,
                onPressed: onGenerate,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
