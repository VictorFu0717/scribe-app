import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../providers/auth_controller.dart';
import '../../providers/settings_controller.dart';
import '../../providers/translation_models_controller.dart';
import '../../services/on_device_translator.dart';
import '../../widgets/language_picker.dart';
import '../../widgets/speaker_count_picker.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _urlCtrl;

  @override
  void initState() {
    super.initState();
    // 在 initState 讀(ref 有效);不可用 late-field 初始化,否則 Mock 模式下
    // 欄位不顯示、_urlCtrl 從未存取,會延遲到 dispose 才初始化而 ref 已失效。
    _urlCtrl = TextEditingController(text: ref.read(settingsProvider).baseUrl);
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          // ── 連線 ──
          _header('連線'),
          SwitchListTile(
            title: const Text('使用 Mock 模式'),
            subtitle: const Text('無需 server 即可示範完整流程'),
            value: settings.useMock,
            onChanged: notifier.setUseMock,
          ),
          if (!settings.useMock) ...[
            SwitchListTile(
              title: const Text('略過登入(開發用)'),
              subtitle: const Text('後端尚未做帳號驗證時,直接進入 App'),
              value: !settings.requireLogin,
              onChanged: (v) => notifier.setRequireLogin(!v),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                controller: _urlCtrl,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: 'Server 位址',
                  hintText: 'http://192.168.x.x:8005',
                  prefixIcon: const Icon(Icons.dns_outlined),
                  suffixIcon: IconButton(
                    tooltip: '儲存',
                    icon: const Icon(Icons.check),
                    onPressed: () {
                      notifier.setBaseUrl(_urlCtrl.text);
                      _toast('已更新 Server 位址');
                    },
                  ),
                ),
                onSubmitted: (_) {
                  notifier.setBaseUrl(_urlCtrl.text);
                  _toast('已更新 Server 位址');
                },
              ),
            ),
            _note('App 只連這一個位址;逐字稿、摘要、AI 助理都由 server 內部處理'
                '(不直連任何模型服務)。'),
          ],

          const Divider(),
          // ── 轉錄 ──
          _header('轉錄'),
          SwitchListTile(
            title: const Text('錄音時螢幕常亮'),
            subtitle: const Text('避免自動鎖屏中斷長時間背景錄音'),
            value: settings.keepScreenOn,
            onChanged: notifier.setKeepScreenOn,
          ),
          SwitchListTile(
            title: const Text('說話者辨識(diarization)'),
            subtitle: const Text('逐字稿標示不同說話者'),
            value: settings.diarization,
            onChanged: notifier.setDiarization,
          ),
          if (settings.diarization)
            ListTile(
              title: const Text('指定說話者人數'),
              subtitle: Text(settings.speakerCount == null
                  ? '自動偵測'
                  : '${settings.speakerCount} 人'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _pickSpeakerCount(notifier, settings),
            ),

          const Divider(),
          // ── 翻譯 ──
          _header('翻譯'),
          SwitchListTile(
            title: const Text('開啟翻譯'),
            subtitle: const Text('錄音時與會議逐字稿都顯示雙語(在手機上離線翻譯)'),
            value: settings.translationEnabled,
            onChanged: (v) async {
              await notifier.setTranslationEnabled(v);
              // 一開啟就先把目前方向的模型備妥,不要等到開會才下載。
              if (v) {
                final s = ref.read(settingsProvider);
                ref
                    .read(translationModelsProvider.notifier)
                    .ensureDownloaded([s.translationSource, s.translationTarget]);
              }
            },
          ),
          if (settings.translationEnabled) ...[
            // 來源/目標各自一列(直觀),右側「⇄」一鍵反轉方向。
            ListTile(
              leading: const Icon(Icons.record_voice_over_outlined),
              title: const Text('說話的語言'),
              subtitle:
                  Text(translationLanguageLabel(settings.translationSource)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final code = await showLanguagePicker(context,
                    title: '說話的語言', current: settings.translationSource);
                if (code != null) {
                  await notifier.setTranslationLanguages(source: code);
                  await ref
                      .read(translationModelsProvider.notifier)
                      .ensureDownloaded([code]);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.translate_rounded),
              title: const Text('翻譯成'),
              subtitle:
                  Text(translationLanguageLabel(settings.translationTarget)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final code = await showLanguagePicker(context,
                    title: '翻譯成', current: settings.translationTarget);
                if (code != null) {
                  await notifier.setTranslationLanguages(target: code);
                  await ref
                      .read(translationModelsProvider.notifier)
                      .ensureDownloaded([code]);
                }
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await notifier.swapTranslationLanguages();
                    final s = ref.read(settingsProvider);
                    await ref
                        .read(translationModelsProvider.notifier)
                        .ensureDownloaded(
                            [s.translationSource, s.translationTarget]);
                  },
                  icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                  label: Text(
                      '交換方向(改成 '
                      '${translationLanguageLabel(settings.translationTarget)}'
                      ' → '
                      '${translationLanguageLabel(settings.translationSource)})'),
                  style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact),
                ),
              ),
            ),
            _ModelStatusTile(
                codes: [settings.translationSource, settings.translationTarget]),
            _note('翻譯在手機上離線進行(零延遲、不佔用 server)。'
                '每個語言的模型約 30MB,下載後永久離線可用;App 啟動時會自動先備妥中文與英文。'),
          ],

          const Divider(),
          _header('關於'),
          const ListTile(
            title: Text('版本'),
            subtitle: Text('${AppConfig.appName} · MVP (Flutter)'),
          ),

          // 帳號:登出(僅已登入時顯示)。
          if (ref.watch(authControllerProvider).isAuthenticated) ...[
            const Divider(),
            _header('帳號'),
            ListTile(
              leading: Icon(Icons.logout_rounded,
                  color: Theme.of(context).colorScheme.error),
              title: Text('登出',
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
              onTap: () => ref.read(authControllerProvider.notifier).logout(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _header(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
        child: Text(text,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
                color: Theme.of(context).colorScheme.primary)),
      );

  Widget _note(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Text(text,
            style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: Theme.of(context).colorScheme.outline)),
      );

  Future<void> _pickSpeakerCount(
      SettingsController notifier, Settings settings) async {
    final result = await showSpeakerCountPicker(context);
    if (result == null) return;
    notifier.setSpeakerCount(result == -1 ? null : result);
  }

}

/// 顯示目前翻譯方向所需語言模型的狀態,並可手動下載/重試。
///
/// ML Kit 的下載 API 不回報進度,所以「下載中」只能顯示為進行中而非百分比。
class _ModelStatusTile extends ConsumerStatefulWidget {
  const _ModelStatusTile({required this.codes});
  final List<String> codes;

  @override
  ConsumerState<_ModelStatusTile> createState() => _ModelStatusTileState();
}

class _ModelStatusTileState extends ConsumerState<_ModelStatusTile> {
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(_ModelStatusTile old) {
    super.didUpdateWidget(old);
    if (old.codes.join() != widget.codes.join()) _refresh();
  }

  void _refresh() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(translationModelsProvider.notifier).refresh(widget.codes);
    });
  }

  @override
  Widget build(BuildContext context) {
    final models = ref.watch(translationModelsProvider);
    final scheme = Theme.of(context).colorScheme;
    final notifier = ref.read(translationModelsProvider.notifier);
    final needsAction = widget.codes.any((c) =>
        models[c] == LanguageModelState.absent ||
        models[c] == LanguageModelState.failed);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('語言模型',
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: scheme.outline)),
          const SizedBox(height: 4),
          for (final code in widget.codes)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                children: [
                  _icon(models[code] ?? LanguageModelState.unknown, scheme),
                  const SizedBox(width: 6),
                  Text(
                    '${translationLanguageLabel(code)} · '
                    '${_label(models[code] ?? LanguageModelState.unknown)}',
                    style: TextStyle(fontSize: 12.5, color: scheme.outline),
                  ),
                ],
              ),
            ),
          if (needsAction)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: OutlinedButton.icon(
                onPressed: () => notifier.ensureDownloaded(widget.codes),
                icon: const Icon(Icons.download_rounded, size: 18),
                label: const Text('下載缺少的語言模型'),
                style:
                    OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
              ),
            ),
        ],
      ),
    );
  }

  Widget _icon(LanguageModelState s, ColorScheme scheme) {
    switch (s) {
      case LanguageModelState.ready:
        return Icon(Icons.check_circle_rounded, size: 14, color: scheme.primary);
      case LanguageModelState.downloading:
        return SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary),
        );
      case LanguageModelState.failed:
        return Icon(Icons.error_outline_rounded, size: 14, color: scheme.error);
      case LanguageModelState.absent:
        return Icon(Icons.cloud_download_outlined,
            size: 14, color: scheme.outline);
      case LanguageModelState.unknown:
        return Icon(Icons.help_outline_rounded, size: 14, color: scheme.outline);
    }
  }

  String _label(LanguageModelState s) => switch (s) {
        LanguageModelState.ready => '已就緒(可離線)',
        LanguageModelState.downloading => '下載中…',
        LanguageModelState.failed => '下載失敗,可重試',
        LanguageModelState.absent => '尚未下載(約 30MB)',
        LanguageModelState.unknown => '檢查中…',
      };
}
