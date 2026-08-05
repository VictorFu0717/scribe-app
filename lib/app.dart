import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/app_config.dart';
import 'core/theme/app_theme.dart';
import 'providers/translation_models_controller.dart';
import 'routing/app_router.dart';

class MeetingAssistantApp extends ConsumerStatefulWidget {
  const MeetingAssistantApp({super.key});

  @override
  ConsumerState<MeetingAssistantApp> createState() =>
      _MeetingAssistantAppState();
}

class _MeetingAssistantAppState extends ConsumerState<MeetingAssistantApp> {
  @override
  void initState() {
    super.initState();
    // 背景預先備妥中/英翻譯模型(各約 30MB),避免開會當下才下載而前幾句沒有譯文。
    // 刻意不 await:失敗只是回到「用到才下載」,不該影響 App 啟動。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(translationModelsProvider.notifier).preloadDefaults();
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: router,
      locale: const Locale('zh', 'TW'),
      supportedLocales: const [
        Locale('zh', 'TW'),
        Locale('en'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
