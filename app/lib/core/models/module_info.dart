import 'package:flutter/material.dart';

/// 模块信息模型
///
/// 表示从后端获取的单个AI模型模块信息
class ModuleInfo {
  /// 模型名称（一级名称），如 "QwenASR"
  final String name;

  /// 类型标识，如 "qwen"
  final String type;

  /// 模型名称（二级名称），如 "gummy-realtime-v1"
  final String modelName;

  /// 模型描述
  final String description;

  /// 是否启用
  final bool enabled;

  const ModuleInfo({
    required this.name,
    required this.type,
    required this.modelName,
    required this.description,
    required this.enabled,
  });

  /// 从JSON创建ModuleInfo实例
  factory ModuleInfo.fromJson(Map<String, dynamic> json) {
    return ModuleInfo(
      name: json['name'] as String,
      type: json['type'] as String? ?? '',
      modelName: json['model_name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? true,
    );
  }

  /// 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'type': type,
      'model_name': modelName,
      'description': description,
      'enabled': enabled,
    };
  }

  /// 获取显示名称，格式为 "一级名称:二级名称"
  /// 如果没有二级名称，则只显示一级名称
  String get displayName => modelName.isNotEmpty ? '$name:$modelName' : name;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is ModuleInfo && other.name == name;
  }

  @override
  int get hashCode => name.hashCode;
}

/// 模块类型枚举
///
/// 定义所有支持的AI模块类型，包括ASR、TTS、LLM等
enum ModuleType {
  /// 语音识别
  asr('ASR', '语音识别', Icons.mic),

  /// 语音合成
  tts('TTS', '语音合成', Icons.volume_up),

  /// 大语言模型
  llm('LLM', '语言模型', Icons.psychology),

  /// 语音活动检测
  vad('VAD', '语音检测', Icons.graphic_eq),

  /// 记忆管理
  memory('Memory', '记忆管理', Icons.storage),

  /// 意图识别
  intent('Intent', '意图识别', Icons.lightbulb),

  /// 视觉语言模型
  vlm('VLM', '视觉模型', Icons.visibility);

  /// 模块类型代码
  final String code;

  /// 显示标签
  final String label;

  /// 关联图标
  final IconData icon;

  const ModuleType(this.code, this.label, this.icon);
}
