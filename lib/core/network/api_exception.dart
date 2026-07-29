/// 統一的 API 錯誤型別,方便 UI 顯示可讀訊息。
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.cause});

  final String message;
  final int? statusCode;
  final Object? cause;

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() =>
      'ApiException(${statusCode ?? '-'}): $message';

  factory ApiException.network(Object error) =>
      ApiException('網路連線失敗,請確認 server 位址與網路狀態。', cause: error);

  factory ApiException.fromResponse(int status, String body) {
    String msg;
    switch (status) {
      case 401:
        msg = '登入已失效,請重新登入。';
        break;
      case 403:
        msg = '沒有存取權限。';
        break;
      case 404:
        msg = '找不到資源。';
        break;
      case >= 500:
        msg = 'Server 發生錯誤($status)。';
        break;
      default:
        msg = '請求失敗($status)。';
    }
    return ApiException(msg, statusCode: status, cause: body);
  }
}
