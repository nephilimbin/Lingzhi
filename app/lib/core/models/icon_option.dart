import 'package:flutter/material.dart';

/// 预定义的图标选项
///
/// 包含可选择的图标及其对应的颜色配置
class IconOption {
  final IconData icon;
  final String name;
  final Color backgroundColor;
  final Color iconColor;

  const IconOption({
    required this.icon,
    required this.name,
    required this.backgroundColor,
    required this.iconColor,
  });
}

/// 可选图标列表
const List<IconOption> availableIcons = [
  IconOption(
    icon: Icons.smart_toy,
    name: '机器人',
    backgroundColor: Color(0xFF9C27B0),
    iconColor: Color(0xFFFFFFFF),
  ),
  IconOption(
    icon: Icons.psychology,
    name: '心理',
    backgroundColor: Color(0xFF673AB7),
    iconColor: Color(0xFFFFFFFF),
  ),
  IconOption(
    icon: Icons.support_agent,
    name: '客服',
    backgroundColor: Color(0xFF3F51B5),
    iconColor: Color(0xFFFFFFFF),
  ),
  IconOption(
    icon: Icons.assistant,
    name: '助手',
    backgroundColor: Color(0xFF2196F3),
    iconColor: Color(0xFFFFFFFF),
  ),
  IconOption(
    icon: Icons.auto_awesome,
    name: '星光',
    backgroundColor: Color(0xFF03A9F4),
    iconColor: Color(0xFFFFFFFF),
  ),
  IconOption(
    icon: Icons.emoji_objects,
    name: '灵感',
    backgroundColor: Color(0xFF00BCD4),
    iconColor: Color(0xFFFFFFFF),
  ),
  IconOption(
    icon: Icons.lightbulb,
    name: '灯泡',
    backgroundColor: Color(0xFF009688),
    iconColor: Color(0xFFFFFFFF),
  ),
  IconOption(
    icon: Icons.stars,
    name: '星星',
    backgroundColor: Color(0xFF4CAF50),
    iconColor: Color(0xFFFFFFFF),
  ),
  IconOption(
    icon: Icons.flutter_dash,
    name: '小鸟',
    backgroundColor: Color(0xFF8BC34A),
    iconColor: Color(0xFFFFFFFF),
  ),
  IconOption(
    icon: Icons.sentiment_satisfied,
    name: '笑脸',
    backgroundColor: Color(0xFFCDDC39),
    iconColor: Color(0xFF000000),
  ),
  IconOption(
    icon: Icons.pets,
    name: '宠物',
    backgroundColor: Color(0xFFFF9800),
    iconColor: Color(0xFFFFFFFF),
  ),
  IconOption(
    icon: Icons.workspace_premium,
    name: '高级',
    backgroundColor: Color(0xFFF44336),
    iconColor: Color(0xFFFFFFFF),
  ),
];
