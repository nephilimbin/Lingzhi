class HttpHeaders {
  static const String xSessionId = 'X-Session-ID';
  static const String deviceId = 'device-id';
  static const String authorization = 'Authorization';
  // 未来可以添加其他 WebSocket 连接或 HTTP 请求中用到的 Header Key
}

// 如果 Query 参数也由此处管理，可以像下面这样添加 (虽然本次主要关注Header):
class QueryParams {
  static const String token = 'token';
  static const String deviceId = 'deviceId';
}

// API 基础地址配置
class ApiConstants {
  static const String baseUrl = 'http://localhost:8000/api/v1';
}
