import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:ai_assistant/core/models/module_info.dart';
import 'package:ai_assistant/core/utils/app_logger.dart';
import 'package:http/io_client.dart';

/// 模块API服务
///
/// 负责从后端服务器获取可用的AI模块列表
class ModulesApi {
  /// 私有构造函数，防止实例化
  ModulesApi._internal();
  /// 请求超时时间
  static const _timeout = Duration(seconds: 10);

  /// 是否允许自签名证书（开发环境）
  static const bool _allowSelfSignedCerts = true;

  /// 创建自定义HTTP客户端，支持自签名证书
  static http.Client _createHttpClient() {
    final httpClient = HttpClient();
    // 允许自签名证书（仅用于开发环境）
    if (_allowSelfSignedCerts) {
      httpClient.badCertificateCallback = (X509Certificate cert, String host, int port) {
        logI('ModulesApi: 接受自签名证书: $host:$port');
        return true;
      };
    }
    return IOClient(httpClient);
  }

  /// 从指定服务器获取可用模块列表
  ///
  /// [baseUrl] WebSocket服务器地址，会自动转换为HTTP地址
  /// 返回包含模块列表和默认配置的响应对象
  ///
  /// 抛出 [Exception] 当请求失败或解析失败时
  static Future<ModulesResponse> fetchModules(String baseUrl) async {
    try {
      // 将WebSocket URL转换为HTTP URL
      var httpUrl = baseUrl;
      if (httpUrl.startsWith('ws://')) {
        httpUrl = httpUrl.replaceFirst('ws://', 'http://');
      } else if (httpUrl.startsWith('wss://')) {
        httpUrl = httpUrl.replaceFirst('wss://', 'https://');
      }

      // 移除路径部分，只保留协议和主机
      final uri = Uri.parse(httpUrl);
      final cleanUrl =
          '${uri.scheme}://${uri.host}${uri.port > 0 ? ':${uri.port}' : ''}';
      final modulesUri = Uri.parse('$cleanUrl/api/v1/config/modules');

      final client = _createHttpClient();
      final response = await client.get(modulesUri).timeout(_timeout);
      client.close();

      if (response.statusCode == 200) {
        final data =
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

        final modulesResponse = ModulesResponse.fromJson(data);

        return modulesResponse;
      } else if (response.statusCode == 404) {
        // 服务器不支持模块API，返回空结果
        return const ModulesResponse(
          modules: <String, List<ModuleInfo>>{},
          defaultSelectedModule: <String, String>{},
        );
      } else {
        throw Exception('获取模块列表失败: HTTP ${response.statusCode}');
      }
    } on SocketException catch (e) {
      throw Exception('网络连接失败: $e');
    } on HttpException catch (e) {
      throw Exception('HTTP请求失败: $e');
    } catch (e) {
      throw Exception('网络请求失败: $e');
    }
  }
}

/// 模块列表响应
///
/// 包含可用模块列表和系统默认选中配置
class ModulesResponse {
  /// 模块类型到模块列表的映射
  final Map<String, List<ModuleInfo>> modules;

  /// 系统默认选中的模块配置
  /// key: 模块类型代码 (如 'VAD', 'ASR', 'LLM')
  /// value: 默认选中的模块名称
  final Map<String, String> defaultSelectedModule;

  const ModulesResponse({
    required this.modules,
    required this.defaultSelectedModule,
  });

  /// 从JSON创建实例
  factory ModulesResponse.fromJson(Map<String, dynamic> json) {
    // 解析 modules
    final modulesJson = json['modules'] as Map<String, dynamic>? ?? {};
    final modules = <String, List<ModuleInfo>>{};
    for (final entry in modulesJson.entries) {
      final moduleList = entry.value as List;
      modules[entry.key] =
          moduleList
              .map((item) => ModuleInfo.fromJson(item as Map<String, dynamic>))
              .toList();
    }

    // 解析 defaultSelectedModule
    final defaultSelectedModuleJson =
        json['default_selected_module'] as Map<String, dynamic>? ?? {};
    final defaultSelectedModule = defaultSelectedModuleJson.map(
      (key, value) => MapEntry(key, value.toString()),
    );

    return ModulesResponse(
      modules: modules,
      defaultSelectedModule: defaultSelectedModule,
    );
  }
}
