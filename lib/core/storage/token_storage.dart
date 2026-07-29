import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../models/auth_token.dart';

/// JWT 安全儲存(iOS Keychain / Android EncryptedSharedPreferences)。
class TokenStorage {
  TokenStorage([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _key = 'auth_token';

  AuthToken? _cached;

  Future<AuthToken?> read() async {
    if (_cached != null) return _cached;
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    try {
      _cached = AuthToken.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      return _cached;
    } catch (_) {
      await clear();
      return null;
    }
  }

  Future<void> write(AuthToken token) async {
    _cached = token;
    await _storage.write(key: _key, value: jsonEncode(token.toJson()));
  }

  Future<void> clear() async {
    _cached = null;
    await _storage.delete(key: _key);
  }
}
