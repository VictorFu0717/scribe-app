import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../routing/app_router.dart';
import '../../services/audio_import.dart';
import '../../services/incoming_file.dart';
import '../../widgets/upload_progress_dialog.dart';
import '../assistant/assistant_screen.dart';
import '../meetings/meetings_list_screen.dart';
import '../settings/settings_screen.dart';

/// 底部三分頁:會議記錄 / AI 助理(跨全部會議)/ 設定。
/// 用 IndexedStack 保留各分頁狀態。
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell>
    with WidgetsBindingObserver {
  int _index = 0;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 原生端收到分享時會主動通知(App 已開著的情況即時反應)。
    IncomingFile.onIncoming(_checkIncomingFile);
    // 由分享動作冷啟動 App 時,檔案已在原生端等著。
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkIncomingFile());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // App 已在執行時被分享喚起:回到前景才拿得到。
    if (state == AppLifecycleState.resumed) _checkIncomingFile();
  }

  /// 取走並匯入從其他 App 分享進來的音檔(例如 iPhone 語音備忘錄)。
  Future<void> _checkIncomingFile() async {
    if (_importing) return;
    final path = await IncomingFile.take();
    if (path == null || !mounted) return;

    _importing = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const UploadProgressDialog(title: '正在匯入分享的音檔…'),
    );
    try {
      final meetingId = await importAudioFile(ref, path);
      if (!mounted) return;
      Navigator.of(context).pop(); // 關閉「處理中」
      context.push(Routes.meeting(meetingId));
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(e is ApiException ? e.message : '匯入分享的音檔失敗:$e'),
        ));
      }
    } finally {
      _importing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          MeetingsListScreen(),
          // 跨全部會議的助理(scope 空);與個別會議詳情內的助理分頁區分。
          AssistantScreen(scope: '', title: 'AI 助理'),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.description_outlined),
            selectedIcon: Icon(Icons.description),
            label: '會議記錄',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome),
            label: 'AI 助理',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '設定',
          ),
        ],
      ),
    );
  }
}
