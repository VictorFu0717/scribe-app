import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_exception.dart';
import '../models/auth_token.dart';
import 'service_providers.dart';
import 'settings_controller.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthState {
  const AuthState({
    this.status = AuthStatus.unknown,
    this.token,
    this.loading = false,
    this.error,
  });

  final AuthStatus status;
  final AuthToken? token;
  final bool loading;
  final String? error;

  bool get isAuthenticated => status == AuthStatus.authenticated;

  AuthState copyWith({
    AuthStatus? status,
    AuthToken? token,
    bool? loading,
    String? error,
    bool clearError = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      token: token ?? this.token,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    // dev:關閉「需要登入」時直接視為已登入(適用尚未做 auth 的後端)。
    final requireLogin =
        ref.watch(settingsProvider.select((s) => s.requireLogin));
    if (!requireLogin) {
      return const AuthState(
        status: AuthStatus.authenticated,
        token: AuthToken(accessToken: 'dev-no-login'),
      );
    }
    _restore();
    return const AuthState();
  }

  Future<void> _restore() async {
    final token = await ref.read(tokenStorageProvider).read();
    if (token != null && !token.isExpired) {
      state = AuthState(status: AuthStatus.authenticated, token: token);
    } else {
      state = const AuthState(status: AuthStatus.unauthenticated);
    }
  }

  Future<bool> login({
    required String username,
    required String password,
  }) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final token = await ref
          .read(backendProvider)
          .login(username: username, password: password);
      // mock 後端不會經過 TokenStorage,補寫一次以利 restore。
      await ref.read(tokenStorageProvider).write(token);
      state = AuthState(status: AuthStatus.authenticated, token: token);
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(loading: false, error: e.message);
      return false;
    } catch (e) {
      state = state.copyWith(loading: false, error: '登入失敗:$e');
      return false;
    }
  }

  Future<void> logout() async {
    await ref.read(tokenStorageProvider).clear();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }
}
