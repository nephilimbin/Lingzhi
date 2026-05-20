import 'package:flutter/material.dart';

/// 服务选择器按钮
///
/// 现代化的下拉选择器，用于选择服务类型或具体配置
class ServiceSelectorButton extends StatelessWidget {
  /// 选择器标题
  final String title;

  /// 当前选中的值
  final String? selectedValue;

  /// 是否可用
  final bool enabled;

  /// 选择图标
  final IconData? icon;

  /// 点击回调
  final VoidCallback? onTap;

  /// 占位符文本
  final String placeholder;

  const ServiceSelectorButton({
    required this.title,
    required this.onTap,
    super.key,
    this.selectedValue,
    this.enabled = true,
    this.icon,
    this.placeholder = '请选择',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: enabled ? theme.colorScheme.onSurface : Colors.grey,
            ),
          ),
        ),
        // 选择按钮
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: enabled
                    ? (isDark ? const Color(0xFF1E1E1E) : Colors.white)
                    : (isDark ? const Color(0xFF2A2A2A) : Colors.grey.shade100),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: enabled
                      ? (isDark ? const Color(0xFF3A3A3A) : Colors.grey.shade200)
                      : Colors.grey.shade200,
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  // 左侧图标（如果有）
                  if (icon != null) ...[
                    Icon(
                      icon,
                      size: 20,
                      color: enabled
                          ? (isDark ? const Color(0xFF4A90E2) : Colors.blue.shade600)
                          : Colors.grey,
                    ),
                    const SizedBox(width: 12),
                  ],
                  // 选中值或占位符
                  Expanded(
                    child: Text(
                      selectedValue ?? placeholder,
                      style: TextStyle(
                        fontSize: 15,
                        color: selectedValue != null
                            ? (enabled
                                ? theme.colorScheme.onSurface
                                : Colors.grey)
                            : (isDark ? const Color(0xFF757575) : Colors.grey.shade500),
                        fontWeight: selectedValue != null
                            ? FontWeight.w500
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                  // 右侧箭头图标
                  Icon(
                    Icons.arrow_drop_down,
                    size: 24,
                    color: enabled
                        ? (isDark ? const Color(0xFF757575) : Colors.grey.shade600)
                        : Colors.grey.shade400,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
