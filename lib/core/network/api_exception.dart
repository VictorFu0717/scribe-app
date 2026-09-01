import 'dart:convert';

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
    // scribe 用 FastAPI 的 HTTPException,錯誤訊息在 detail,而且寫得很具體
    // (如「會議狀態為 transcribing,請等轉錄完成後再編輯」)。優先用它 ——
    // 只顯示「請求失敗(409)」對使用者毫無幫助。
    final detail = _detailOf(body);

    String msg;
    switch (status) {
      case 401:
        // 這個一律用自己的說法:server 的 detail 是給開發者看的。
        msg = '登入已失效,請重新登入。';
        break;
      case 403:
        msg = detail ?? '沒有存取權限。';
        break;
      case 404:
        msg = detail ?? '找不到資源。';
        break;
      case >= 500:
        msg = 'Server 發生錯誤($status)。';
        break;
      default:
        msg = detail ?? '請求失敗($status)。';
    }
    return ApiException(msg, statusCode: status, cause: body);
  }

  /// 從 FastAPI 的錯誤 body 取出可顯示的 detail;取不到回 null。
  static String? _detailOf(String body) {
    if (body.isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      final detail = decoded['detail'];
      // 422 的 detail 是一串驗證錯誤物件,直接顯示只會是一堆看不懂的 JSON。
      if (detail is! String) return null;
      final trimmed = detail.trim();
      return trimmed.isEmpty ? null : trimmed;
    } catch (_) {
      return null; // body 不是 JSON(如 proxy 回的 HTML)
    }
  }
}
