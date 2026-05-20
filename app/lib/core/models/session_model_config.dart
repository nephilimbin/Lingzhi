import 'package:flutter/foundation.dart';
import 'package:ai_assistant/core/models/server_model_config.dart';

/// Session模型配置
///
/// 用于存储单个对话（session）层级的模型配置
/// 这个配置独立于服务器的全局模型配置（ServerModelConfig）
@immutable
class SessionModelConfig {
  /// 关联的服务器ID
  final String serverId;

  /// 模块类型到模型名称的映射
  /// key: 模块类型代码 (如 'asr', 'tts', 'llm')
  /// value: 选中的模型名称，null表示使用服务器默认配置
  final Map<String, String?> selectedModels;

  const SessionModelConfig({
    required this.serverId,
    required this.selectedModels,
  });

  /// 创建副本
  SessionModelConfig copyWith({
    String? serverId,
    Map<String, String?>? selectedModels,
  }) {
    return SessionModelConfig(
      serverId: serverId ?? this.serverId,
      selectedModels: selectedModels ?? this.selectedModels,
    );
  }

  /// 获取指定模块类型的选中模型
  String? getModel(String moduleType) {
    return selectedModels[moduleType];
  }

  /// 设置指定模块类型的模型
  SessionModelConfig setModel(String moduleType, String? modelName) {
    final newModels = Map<String, String?>.from(selectedModels);
    newModels[moduleType] = modelName;
    return copyWith(selectedModels: newModels);
  }

  /// 创建空配置实例（未配置任何模型，使用服务器默认）
  factory SessionModelConfig.empty(String serverId) {
    return SessionModelConfig(
      serverId: serverId,
      selectedModels: {},
    );
  }

  /// 从ServerModelConfig创建SessionModelConfig
  factory SessionModelConfig.fromServerConfig(ServerModelConfig serverConfig) {
    return SessionModelConfig(
      serverId: serverConfig.serverId,
      selectedModels: Map<String, String?>.from(serverConfig.selectedModels),
    );
  }

  /// 从JSON创建实例
  factory SessionModelConfig.fromJson(Map<String, dynamic> json) {
    return SessionModelConfig(
      serverId: json['serverId'] as String,
      selectedModels: Map<String, String?>.from(
        json['selectedModels'] as Map? ?? {},
      ),
    );
  }

  /// 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'serverId': serverId,
      'selectedModels': selectedModels,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is SessionModelConfig &&
        other.serverId == serverId &&
        _mapEquals(other.selectedModels, selectedModels);
  }

  bool _mapEquals(Map<String, String?> a, Map<String, String?> b) {
    if (a.length != b.length) {
      return false;
    }
    for (final key in a.keys) {
      if (a[key] != b[key]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(serverId, selectedModels);
}
