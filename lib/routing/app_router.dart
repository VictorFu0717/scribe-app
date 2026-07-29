import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/assistant/assistant_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/splash_screen.dart';
import '../features/meetings/meeting_detail_screen.dart';
import '../features/meetings/meetings_list_screen.dart';
import '../features/recording/recording_screen.dart';
import '../features/settings/settings_screen.dart';
import '../providers/auth_controller.dart';

/// 路由路徑常數。
class Routes {
  static const splash = '/splash';
  static const login = '/login';
  static const meetings = '/';
  static const record = '/record';
  static const settings = '/settings';
  static const assistant = '/assistant';
  static String meeting(String id) => '/meeting/$id';
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.onDispose(refresh.dispose);
  ref.listen(authControllerProvider.select((s) => s.status),
      (_, _) => refresh.value++);

  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      final status = ref.read(authControllerProvider).status;
      final loc = state.matchedLocation;
      if (status == AuthStatus.unknown) {
        return loc == Routes.splash ? null : Routes.splash;
      }
      if (status == AuthStatus.unauthenticated) {
        return loc == Routes.login ? null : Routes.login;
      }
      // authenticated
      if (loc == Routes.login || loc == Routes.splash) return Routes.meetings;
      return null;
    },
    routes: [
      GoRoute(
          path: Routes.splash,
          builder: (_, _) => const SplashScreen()),
      GoRoute(
          path: Routes.login, builder: (_, _) => const LoginScreen()),
      GoRoute(
          path: Routes.meetings,
          builder: (_, _) => const MeetingsListScreen()),
      GoRoute(
          path: Routes.record,
          builder: (_, _) => const RecordingScreen()),
      GoRoute(
          path: Routes.settings,
          builder: (_, _) => const SettingsScreen()),
      GoRoute(
        path: Routes.assistant,
        builder: (_, _) => const AssistantScreen(scope: '', title: '個人助理'),
      ),
      GoRoute(
        path: '/meeting/:id',
        builder: (_, state) =>
            MeetingDetailScreen(meetingId: state.pathParameters['id']!),
      ),
    ],
  );
});
