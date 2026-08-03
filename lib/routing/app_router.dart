import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/login_screen.dart';
import '../features/auth/register_screen.dart';
import '../features/auth/splash_screen.dart';
import '../features/home/home_shell.dart';
import '../features/meetings/meeting_detail_screen.dart';
import '../features/recording/recording_screen.dart';
import '../features/settings/settings_screen.dart';
import '../providers/auth_controller.dart';

/// 路由路徑常數。
class Routes {
  static const splash = '/splash';
  static const login = '/login';
  static const register = '/register';
  static const meetings = '/';
  static const record = '/record';
  static const settings = '/settings';
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
        // 登入前也要能進「設定」(改 server 位址 / 開 Mock)與註冊。
        const allowed = {Routes.login, Routes.register, Routes.settings};
        return allowed.contains(loc) ? null : Routes.login;
      }
      // authenticated
      if (loc == Routes.login ||
          loc == Routes.register ||
          loc == Routes.splash) {
        return Routes.meetings;
      }
      return null;
    },
    routes: [
      GoRoute(
          path: Routes.splash,
          builder: (_, _) => const SplashScreen()),
      GoRoute(
          path: Routes.login, builder: (_, _) => const LoginScreen()),
      GoRoute(
          path: Routes.register, builder: (_, _) => const RegisterScreen()),
      GoRoute(
          path: Routes.meetings, builder: (_, _) => const HomeShell()),
      GoRoute(
          path: Routes.record,
          builder: (_, _) => const RecordingScreen()),
      // /settings 仍保留:未登入時可從登入頁進入(登入後則是分頁)。
      GoRoute(
          path: Routes.settings,
          builder: (_, _) => const SettingsScreen()),
      GoRoute(
        path: '/meeting/:id',
        builder: (_, state) =>
            MeetingDetailScreen(meetingId: state.pathParameters['id']!),
      ),
    ],
  );
});
