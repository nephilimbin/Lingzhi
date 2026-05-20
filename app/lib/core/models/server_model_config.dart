/// 服务器模型配置
///
/// 为每个服务器配置存储各个模块类型选中的模型名称
class ServerModelConfig {
  /// 关联的服务器ID
  final String serverId;

  /// 模块类型到模型名称的映射
  /// key: 模块类型代码 (如 'asr', 'tts', 'llm')
  /// value: 选中的模型名称，null表示未配置
  final Map<String, String?> selectedModels;

  const ServerModelConfig({
    required this.serverId,
    required this.selectedModels,
  });

  /// 创建副本
  ServerModelConfig copyWith({
    String? serverId,
    Map<String, String?>? selectedModels,
  }) {
    return ServerModelConfig(
      serverId: serverId ?? this.serverId,
      selectedModels: selectedModels ?? this.selectedModels,
    );
  }

  /// 获取指定模块类型的选中模型
  String? getModel(String moduleType) {
    return selectedModels[moduleType];
  }

  /// 设置指定模块类型的模型
  ServerModelConfig setModel(String moduleType, String? modelName) {
    final newModels = Map<String, String?>.from(selectedModels);
    newModels[moduleType] = modelName;
    return copyWith(selectedModels: newModels);
  }

  /// 创建空配置实例（未配置任何模型）
  factory ServerModelConfig.empty(String serverId) {
    return ServerModelConfig(
      serverId: serverId,
      selectedModels: {},
    );
  }

  /// 从JSON创建实例
  factory ServerModelConfig.fromJson(Map<String, dynamic> json) {
    return ServerModelConfig(
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
    return other is ServerModelConfig &&
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
