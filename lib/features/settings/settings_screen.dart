import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../providers/settings_controller.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _urlCtrl =
      TextEditingController(text: ref.read(settingsProvider).baseUrl);

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
            title: const Text('即時串流轉錄'),
            subtitle: Text(settings.streamingTranscription
                ? '邊錄邊出字(WebSocket)'
                : '錄完整檔後上傳轉錄'),
            value: settings.streamingTranscription,
            onChanged: notifier.setStreamingTranscription,
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
          _header('關於'),
          const ListTile(
            title: Text('版本'),
            subtitle: Text('${AppConfig.appName} · MVP (Flutter)'),
          ),
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
    final result = await showModalBottomSheet<int>(
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
    notifier.setSpeakerCount(result == -1 ? null : result);
  }
}
