import 'package:flutter/material.dart';

/// 定义服务支持的功能集
class ServiceCapabilities {
  final bool supportsVoiceInput;
  final bool supportsStreamingText;

  const ServiceCapabilities({
    this.supportsVoiceInput = false,
    this.supportsStreamingText = false,
  });
}

/// 服务图标配置类
///
/// 用于定义聊天服务的图标显示方式
class ServiceIcon {
  /// 图标数据
  final IconData iconData;

  /// 图标背景颜色
  final Color backgroundColor;

  /// 图标颜色
  final Color iconColor;

  const ServiceIcon({
    required this.iconData,
    required this.backgroundColor,
    required this.iconColor,
  });

  /// 从JSON创建ServiceIcon实例
  factory ServiceIcon.fromJson(Map<String, dynamic> json) {
    return ServiceIcon(
      iconData: _getIconFromString(json['icon'] as String? ?? 'smart_toy'),
      backgroundColor: Color(
        int.parse(
          json['backgroundColor'] as String? ?? '0xFF9C27B0',
        ),
      ),
      iconColor: Color(
        int.parse(json['iconColor'] as String? ?? '0xFFFFFFFF'),
      ),
    );
  }

  /// 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'icon': _getStringFromIcon(iconData),
      // ignore: deprecated_member_use
      'backgroundColor': '0x${backgroundColor.value.toRadixString(16).toUpperCase()}',
      // ignore: deprecated_member_use
      'iconColor': '0x${iconColor.value.toRadixString(16).toUpperCase()}',
    };
  }

  /// 根据字符串获取对应的IconData
  static IconData _getIconFromString(String iconString) {
    switch (iconString) {
      case 'smart_toy':
        return Icons.smart_toy;
      case 'psychology':
        return Icons.psychology;
      case 'support_agent':
        return Icons.support_agent;
      case 'assistant':
        return Icons.assistant;
      case 'auto_awesome':
        return Icons.auto_awesome;
      case 'emoji_objects':
        return Icons.emoji_objects;
      case 'lightbulb':
        return Icons.lightbulb;
      case 'stars':
        return Icons.stars;
      case 'flutter_dash':
        return Icons.flutter_dash;
      case 'sentiment_satisfied':
        return Icons.sentiment_satisfied;
      case 'pets':
        return Icons.pets;
      case 'workspace_premium':
        return Icons.workspace_premium;
      default:
        return Icons.smart_toy;
    }
  }

  /// 将IconData转换为字符串
  static String _getStringFromIcon(IconData icon) {
    switch (icon) {
      case Icons.psychology:
        return 'psychology';
      case Icons.support_agent:
        return 'support_agent';
      case Icons.assistant:
        return 'assistant';
      case Icons.auto_awesome:
        return 'auto_awesome';
      case Icons.emoji_objects:
        return 'emoji_objects';
      case Icons.lightbulb:
        return 'lightbulb';
      case Icons.stars:
        return 'stars';
      case Icons.flutter_dash:
        return 'flutter_dash';
      case Icons.sentiment_satisfied:
        return 'sentiment_satisfied';
      case Icons.pets:
        return 'pets';
      case Icons.workspace_premium:
        return 'workspace_premium';
      default:
        return 'smart_toy';
    }
  }

  /// 创建默认的ServiceIcon实例
  factory ServiceIcon.defaultIcon() {
    return const ServiceIcon(
      iconData: Icons.smart_toy,
      backgroundColor: Color(0xFF9C27B0),
      iconColor: Color(0xFFFFFFFF),
    );
  }
}

/// 所有聊天服务配置的抽象基类
abstract class ChatServiceConfig {
  final String id;
  final String name;
  final ServiceCapabilities capabilities;
  final ServiceIcon icon;

  const ChatServiceConfig({
    required this.id,
    required this.name,
    required this.capabilities,
    this.icon = const ServiceIcon(
      iconData: Icons.smart_toy,
      backgroundColor: Color(0xFF9C27B0),
      iconColor: Color(0xFFFFFFFF),
    ),
  });

  Map<String, dynamic> toJson();
}
