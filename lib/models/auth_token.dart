/// JWT 憑證,對應 `POST /auth/token` 回應。
class AuthToken {
  const AuthToken({
    required this.accessToken,
    this.refreshToken,
    this.tokenType = 'Bearer',
    this.expiresAt,
  });

  final String accessToken;
  final String? refreshToken;
  final String tokenType;
  final DateTime? expiresAt;

  bool get isExpired {
    final exp = expiresAt;
    if (exp == null) return false;
    return DateTime.now().isAfter(exp.subtract(const Duration(seconds: 30)));
  }

  String get authorizationHeader => '$tokenType $accessToken';

  factory AuthToken.fromJson(Map<String, dynamic> json) {
    final expiresIn = json['expires_in'];
    DateTime? expiresAt;
    if (expiresIn is num) {
      expiresAt = DateTime.now().add(Duration(seconds: expiresIn.toInt()));
    } else if (json['expires_at'] is String) {
      expiresAt = DateTime.tryParse(json['expires_at'] as String);
    }
    return AuthToken(
      accessToken: (json['access_token'] ?? json['token']) as String,
      refreshToken: json['refresh_token'] as String?,
      tokenType: (json['token_type'] as String?)?.trim().isNotEmpty == true
          ? _capitalize(json['token_type'] as String)
          : 'Bearer',
      expiresAt: expiresAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'access_token': accessToken,
        if (refreshToken != null) 'refresh_token': refreshToken,
        'token_type': tokenType,
        if (expiresAt != null) 'expires_at': expiresAt!.toIso8601String(),
      };

  static String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1).toLowerCase()}';
}
