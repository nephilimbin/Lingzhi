import 'package:flutter/material.dart';

/// 配置详情卡片
///
/// 显示选中配置的详细信息
class ConfigDetailCard extends StatelessWidget {
  /// 配置名称
  final String name;

  /// 配置详情列表（标签-值对）
  final List<ConfigDetailItem> details;

  const ConfigDetailCard({
    required this.name,
    required this.details,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF3A3A3A) : Colors.grey.shade200,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 配置名称
          Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 18,
                color: Colors.blue.shade600,
              ),
              const SizedBox(width: 8),
              Text(
                '配置详情',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 详情列表
          ...details.map((detail) => _buildDetailItem(detail, isDark)),
        ],
      ),
    );
  }

  Widget _buildDetailItem(ConfigDetailItem detail, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标签
          SizedBox(
            width: 80,
            child: Text(
              detail.label,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? const Color(0xFFB0B0B0) : Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          // 冒号
          Text(
            ': ',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? const Color(0xFFB0B0B0) : Colors.grey.shade600,
            ),
          ),
          // 值
          Expanded(
            child: Text(
              detail.value,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? const Color(0xFFE0E0E0) : Colors.black87,
                fontWeight: FontWeight.w400,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// 配置详情项
class ConfigDetailItem {
  /// 标签
  final String label;

  /// 值
  final String value;

  const ConfigDetailItem({
    required this.label,
    required this.value,
  });
}
