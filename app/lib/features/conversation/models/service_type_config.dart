import 'package:flutter/material.dart';
import 'package:ai_assistant/core/providers/config_provider.dart';

/// 函数类型定义，用于判断是否有配置
typedef HasConfigsChecker = bool Function(ConfigProvider);

/// 服务类型配置
///
/// 用于统一管理各种服务类型的显示信息和配置
class ServiceTypeConfig {
  /// 服务类型标识
  final String id;

  /// 服务显示名称
  final String displayName;

  /// 服务描述
  final String description;

  /// 服务图标
  final IconData icon;

  /// 判断是否有配置的函数
  final HasConfigsChecker hasConfigs;

  const ServiceTypeConfig({
    required this.id,
    required this.displayName,
    required this.description,
    required this.icon,
    required this.hasConfigs,
  });
}

/// 预定义的服务类型配置
///
/// 这是一个常量类，用于提供预定义的服务类型配置实例
class ServiceTypeConfigs {
  // 私有构造函数，防止实例化
  ServiceTypeConfigs._();

  /// 自定义服务（自定义语音服务）
  static const ServiceTypeConfig customService = ServiceTypeConfig(
    id: 'custom_service',
    displayName: '自定义服务',
    description: '使用自定义的自定义语音服务',
    icon: Icons.settings_input_antenna,
    hasConfigs: _hasDiyConfigs,
  );

  /// Dify服务
  static const ServiceTypeConfig difyService = ServiceTypeConfig(
    id: 'dify_service',
    displayName: 'Dify服务',
    description: '使用Dify文本对话服务',
    icon: Icons.chat_bubble_outline,
    hasConfigs: _hasDifyConfigs,
  );

  /// 判断是否有自定义服务配置
  static bool _hasDiyConfigs(ConfigProvider provider) {
    return provider.diyConfigs.isNotEmpty;
  }

  /// 判断是否有Dify服务配置
  static bool _hasDifyConfigs(ConfigProvider provider) {
    return provider.difyConfigs.isNotEmpty;
  }

  /// 获取所有可用的服务类型配置
  static const List<ServiceTypeConfig> all = [customService, difyService];

  /// 获取有配置的服务类型列表
  static List<ServiceTypeConfig> getAvailable(ConfigProvider provider) {
    return all.where((type) => type.hasConfigs(provider)).toList();
  }

  /// 根据ID查找服务配置
  static ServiceTypeConfig? findById(String id) {
    for (final config in all) {
      if (config.id == id) {
        return config;
      }
    }
    return null;
  }
}
