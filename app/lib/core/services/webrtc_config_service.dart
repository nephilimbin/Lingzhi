import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:ai_assistant/core/utils/app_logger.dart';

/// WebRTC 配置模型
class WebRtcConfig {
  final List<IceServer> iceServers;
  final int iceCandidatePoolSize;
  final String iceTransportPolicy;
  final String bundlePolicy;
  final String rtcpMuxPolicy;

  WebRtcConfig({
    required this.iceServers,
    required this.iceCandidatePoolSize,
    required this.iceTransportPolicy,
    required this.bundlePolicy,
    required this.rtcpMuxPolicy,
  });

  factory WebRtcConfig.fromJson(Map<String, dynamic> json) {
    return WebRtcConfig(
      iceServers: (json['iceServers'] as List?)
          ?.map((e) => IceServer.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
      iceCandidatePoolSize: json['iceCandidatePoolSize'] ?? 4,
      iceTransportPolicy: json['iceTransportPolicy'] ?? 'all',
      bundlePolicy: json['bundlePolicy'] ?? 'max-bundle',
      rtcpMuxPolicy: json['rtcpMuxPolicy'] ?? 'require',
    );
  }

  /// 转换为 flutter_webrtc 需要的格式
  Map<String, dynamic> toRTCConfiguration() {
    return {
      'iceServers': iceServers.map((e) => e.toJson()).toList(),
      'iceCandidatePoolSize': iceCandidatePoolSize,
      'iceTransportPolicy': iceTransportPolicy,
      'bundlePolicy': bundlePolicy,
      'rtcpMuxPolicy': rtcpMuxPolicy,
      'sdpSemantics': 'unified-plan',
    };
  }
}

/// ICE 服务器配置
class IceServer {
  final List<String> urls;
  final String? username;
  final String? credential;

  IceServer({
    required this.urls,
    this.username,
    this.credential,
  });

  factory IceServer.fromJson(Map<String, dynamic> json) {
    return IceServer(
      urls: (json['urls'] as List).cast<String>(),
      username: json['username'],
      credential: json['credential'],
    );
  }

  Map<String, dynamic> toJson() {
    final result = <String, dynamic>{'urls': urls};
    if (username != null) {
      result['username'] = username;
    }
    if (credential != null) {
      result['credential'] = credential;
    }
    return result;
  }
}

/// WebRTC 全局配置服务
///
/// 从后端获取全局 WebRTC 配置，无需 session_id
class WebRtcConfigService {
  /// 是否允许自签名证书（开发环境）
  static const bool _allowSelfSignedCerts = true;

  final String serverUrl;

  WebRtcConfigService({required this.serverUrl});

  /// 创建自定义HTTP客户端，支持自签名证书
  static http.Client _createHttpClient() {
    final httpClient = HttpClient();
    // 允许自签名证书（仅用于开发环境）
    if (_allowSelfSignedCerts) {
      httpClient.badCertificateCallback = (X509Certificate cert, String host, int port) {
        logI('接受自签名证书: $host:$port');
        return true;
      };
    }
    return IOClient(httpClient);
  }

  /// 从后端获取全局 WebRTC 配置
  Future<WebRtcConfig?> fetchWebRtcConfig() async {
    http.Client? client;
    try {
      final url = Uri.parse('$serverUrl/api/v1/config/webrtc');

      logI('🔄 从后端获取全局 WebRTC 配置: $url');

      // 创建自定义HTTP客户端（支持自签名证书）
      client = _createHttpClient();

      final response = await client.get(
        url,
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['config'] != null) {
          final config = WebRtcConfig.fromJson(data['config']);
          logI('✅ 全局 WebRTC 配置获取成功');
          return config;
        }
      }

      logW('⚠️ 全局 WebRTC 配置获取失败: HTTP ${response.statusCode}');
      return null;
    } catch (e) {
      logE('❌ 获取全局 WebRTC 配置异常: $e');
      return null;
    } finally {
      client?.close();
    }
  }
}
