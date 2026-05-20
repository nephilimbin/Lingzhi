import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:ai_assistant/core/utils/app_logger.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// 服务器配置信息
class ServerConfigInfo {
  final bool sslEnabled;
  final String recommendedProtocol;
  final int recommendedPort;
  final String message;

  ServerConfigInfo({
    required this.sslEnabled,
    required this.recommendedProtocol,
    required this.recommendedPort,
    required this.message,
  });

  factory ServerConfigInfo.fromJson(Map<String, dynamic> json) {
    return ServerConfigInfo(
      sslEnabled: json['ssl_enabled'] as bool? ?? false,
      recommendedProtocol: json['recommended_protocol'] as String? ?? 'ws',
      recommendedPort: json['recommended_port'] as int? ?? 8000,
      message: json['message'] as String? ?? '',
    );
  }
}

/// 连接测试结果模型
class ConnectionTestResult {
  final bool success;
  final String message;
  final String? errorType; // 新增：错误类型
  final int? handshakeTime;
  final int? connectionTime;
  final String? serverVersion;
  final String? sessionId;

  ConnectionTestResult({
    required this.success,
    required this.message,
    this.errorType,
    this.handshakeTime,
    this.connectionTime,
    this.serverVersion,
    this.sessionId,
  });

  factory ConnectionTestResult.fromJson(Map<String, dynamic> json) {
    return ConnectionTestResult(
      success: json['success'] as bool? ?? false,
      message: json['message'] as String? ?? '未知错误',
      errorType: json['error_type'] as String?, // 新增
      handshakeTime: json['details']?['handshake_time'] as int?,
      connectionTime: json['details']?['connection_time'] as int?,
      serverVersion: json['details']?['server_version'] as String?,
      sessionId: json['details']?['session_id'] as String?,
    );
  }

  @override
  String toString() {
    if (success) {
      final timeInfo = handshakeTime != null ? ' (${handshakeTime}ms)' : '';
      return '$message$timeInfo';
    }
    return message;
  }
}

/// 连接测试异常
class ConnectionTestException implements Exception {
  final String message;

  ConnectionTestException(this.message);

  @override
  String toString() => message;
}

/// 测试超时时间（毫秒）
const int _connectionTestTimeoutMs = 15000;

/// 是否允许自签名证书（开发环境）
const bool _allowSelfSignedCerts = true;

/// 创建自定义HTTP客户端，支持自签名证书
http.Client _createHttpClient() {
  final httpClient = HttpClient();
  // 允许自签名证书（仅用于开发环境）
  if (_allowSelfSignedCerts) {
    httpClient.badCertificateCallback = (
      X509Certificate cert,
      String host,
      int port,
    ) {
      logI('接受自签名证书: $host:$port');
      return true;
    };
  }
  return IOClient(httpClient);
}

/// 测试自定义服务器连接
///
/// 通过后端API代理测试WebSocket服务器连接。
/// 前端调用HTTP API，后端处理实际的WebSocket连接测试。
///
/// 参数:
/// - serverUrl: WebSocket服务器地址（ws://或wss://开头）
/// - macAddress: MAC地址，用于设备认证
/// - token: 可选的认证令牌
///
/// 返回: ConnectionTestResult 测试结果
///
/// 抛出: ConnectionTestException 当网络请求失败时
///
/// HTTP/HTTPS自动回退机制:
/// - 如果用户输入wss://，只尝试https
/// - 如果用户输入ws://，先尝试http，失败后再尝试https
Future<ConnectionTestResult> testDiyConnection({
  required String serverUrl,
  required String macAddress,
  String? token,
}) async {
    logI('开始测试自定义服务连接: $serverUrl');

    // 验证URL格式
    final trimmedUrl = serverUrl.trim();
    if (!trimmedUrl.startsWith('ws://') && !trimmedUrl.startsWith('wss://')) {
      logW('URL格式无效: $trimmedUrl');
      return ConnectionTestResult(
        success: false,
        message: '请输入有效的服务器地址（ws://或wss://开头）',
      );
    }

    // 解析URL获取主机和端口
    final uri = Uri.parse(trimmedUrl);
    final host = uri.host;

    // 确定要尝试的HTTP协议
    // 如果用户输入wss://，只尝试https
    // 如果用户输入ws://，先尝试http，失败后再尝试https
    final useWss = trimmedUrl.startsWith('wss://');
    final schemes = useWss ? ['https'] : ['http', 'https'];

    // 记录最后一个错误信息
    String? lastError;

    for (final scheme in schemes) {
      try {
        final httpBaseUrl = '$scheme://$host';
        // 方案B: 完全依赖用户在 URL 中指定的端口
        // 如果用户没有指定端口，不添加端口号（使用系统默认端口：ws=80, wss=443）
        // 如果用户指定了端口（如 :8000），使用指定的端口
        final baseUrlWithPort = uri.hasPort ? '$httpBaseUrl:${uri.port}' : httpBaseUrl;

        final apiUri = Uri.parse(
          '$baseUrlWithPort/api/v1/config/test-connection',
        );
        logI('尝试使用$scheme请求: $apiUri');

        // 构建请求体
        final requestBody = jsonEncode({
          'server_url': trimmedUrl,
          'mac_address': macAddress,
          if (token != null && token.isNotEmpty) 'token': token,
        });

        // 创建自定义HTTP客户端（支持自签名证书）
        final client = _createHttpClient();

        // 发送POST请求
        final response = await client
            .post(
              apiUri,
              headers: {'Content-Type': 'application/json'},
              body: requestBody,
            )
            .timeout(const Duration(milliseconds: _connectionTestTimeoutMs));

        // 关闭客户端
        client.close();

        logI('响应状态码: ${response.statusCode}');

        // 解析响应
        if (response.statusCode == 200) {
          try {
            final responseData =
                jsonDecode(utf8.decode(response.bodyBytes))
                    as Map<String, dynamic>;
            final result = ConnectionTestResult.fromJson(responseData);

            if (result.success) {
              logI(
                '连接测试成功: ${result.message}, 握手耗时: ${result.handshakeTime}ms',
              );
            } else {
              logW(
                '连接测试失败: ${result.message}, error_type: ${result.errorType}',
              );
            }

            return result;
          } on FormatException catch (e) {
            logE('解析响应失败: $e');
            return ConnectionTestResult(success: false, message: '服务器响应格式错误');
          }
        } else {
          // HTTP错误，继续尝试下一个协议
          lastError = 'HTTP错误 (${response.statusCode})';
          logW('HTTP错误: ${response.statusCode}, 继续尝试下一个协议');
          continue;
        }
      } on http.ClientException catch (e) {
        // 网络错误，继续尝试下一个协议
        lastError = '网络请求失败: ${e.toString()}';
        logW('网络请求失败($scheme): $e, 继续尝试下一个协议');
        continue;
      } on TimeoutException catch (e) {
        // 超时，继续尝试下一个协议
        lastError = '连接测试超时';
        logW('连接测试超时($scheme): $e, 继续尝试下一个协议');
        continue;
      } catch (e) {
        // 其他错误，继续尝试下一个协议
        lastError = '未知错误: ${e.toString()}';
        logW('未知错误($scheme): $e, 继续尝试下一个协议');
        continue;
      }
    }

    // 所有协议都失败，返回最后的错误信息
    logE('所有协议尝试均失败');
    return ConnectionTestResult(
      success: false,
      message: lastError ?? '无法连接到服务器，请检查地址和网络',
    );
  }

/// 获取服务器配置信息
///
/// 参数:
/// - serverUrl: WebSocket服务器地址（ws://或wss://开头）
///
/// 返回: ServerConfigInfo 服务器配置信息，失败返回null
///
/// HTTP/HTTPS自动回退机制:
/// - 如果用户输入wss://，只尝试https
/// - 如果用户输入ws://，先尝试http，失败后再尝试https
Future<ServerConfigInfo?> getServerConfigInfo({
  required String serverUrl,
}) async {
    try {
      final uri = Uri.parse(serverUrl);
      final host = uri.host;

      // 确定要尝试的HTTP协议
      final useWss = serverUrl.startsWith('wss://');
      final schemes = useWss ? ['https'] : ['http', 'https'];

      for (final scheme in schemes) {
        try {
          final baseUrl = '$scheme://$host';
          // 方案B: 完全依赖用户在 URL 中指定的端口
          // 如果用户没有指定端口，不添加端口号（使用系统默认端口）
          final fullUrl = uri.hasPort
              ? '$baseUrl:${uri.port}/api/v1/config/server-info'
              : '$baseUrl/api/v1/config/server-info';

          logI('尝试使用$scheme获取服务器配置: $fullUrl');

          // 创建自定义HTTP客户端（支持自签名证书）
          final client = _createHttpClient();

          final response = await client
              .get(Uri.parse(fullUrl))
              .timeout(const Duration(milliseconds: 5000));

          // 关闭客户端
          client.close();

          if (response.statusCode == 200) {
            final responseData = jsonDecode(utf8.decode(response.bodyBytes));
            final data = responseData as Map<String, dynamic>;
            if (data['success'] == true) {
              logI('通过$scheme成功获取服务器配置: SSL=${data['ssl_enabled']}');
              return ServerConfigInfo.fromJson(data);
            }
          }
        } catch (e) {
          logW('使用$scheme获取服务器配置失败: $e, 继续尝试下一个协议');
          continue;
        }
      }
    } catch (e) {
      logW('获取服务器配置信息失败: $e');
    }
    return null;
}
