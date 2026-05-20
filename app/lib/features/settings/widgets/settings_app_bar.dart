import 'package:flutter/material.dart';

/// 设置页面统一的顶部导航栏组件
///
/// 提供统一的样式：
/// - 标题大小24px
/// - 返回按钮（InkWell + Icon，size=20）
/// - 内边距：horizontal=24, vertical=16
/// - 可选分割线（颜色：深色#3A3A3A，浅色#E5E7EB）
class SettingsAppBar extends StatelessWidget {
  /// 标题文本
  final String title;

  /// 是否显示分割线（默认true）
  final bool showDivider;

  /// 自定义右侧组件
  final Widget? action;

  const SettingsAppBar({
    required this.title,
    super.key,
    this.action,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 顶部导航区域
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Row(
            children: [
              // 返回按钮
              InkWell(
                onTap: () => Navigator.of(context).pop(),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    Icons.arrow_back,
                    color: theme.colorScheme.onSurface,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // 标题
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              // 右侧操作组件（可选）
              if (action != null) action!,
            ],
          ),
        ),
        // 分割线
        if (showDivider)
          Container(
            height: 1,
            color: isDark ? const Color(0xFF3A3A3A) : const Color(0xFFE5E7EB),
          ),
      ],
    );
  }
}
