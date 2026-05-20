import 'package:flutter/material.dart';
import 'package:ai_assistant/core/models/module_info.dart';
import 'package:ai_assistant/core/models/server_model_config.dart';

/// 模型配置卡片
///
/// 显示选中服务器的各个模块类型的模型配置
class ModelConfigCard extends StatelessWidget {
  /// 服务器模型配置
  final ServerModelConfig config;

  const ModelConfigCard({required this.config, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // 获取已配置的模型列表
    final configuredModels = _getConfiguredModels();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? const Color(0xFF3A3A3A) : Colors.grey.shade200, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题
          Row(
            children: [
              Icon(
                Icons.model_training_outlined,
                size: 18,
                color: Colors.blue.shade600,
              ),
              const SizedBox(width: 8),
              Text(
                '已选模型配置',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 模型列表或空状态提示
          if (configuredModels.isEmpty)
            _buildEmptyState(isDark)
          else
            ...configuredModels.map((item) => _buildModelItem(item, isDark)),
        ],
      ),
    );
  }

  /// 构建空状态提示
  Widget _buildEmptyState(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: isDark ? const Color(0xFF757575) : Colors.grey.shade400),
          const SizedBox(width: 8),
          Text(
            '暂未配置任何模型',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? const Color(0xFF757575) : Colors.grey.shade500,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  /// 获取已配置的模型列表
  List<_ModelConfigItem> _getConfiguredModels() {
    final items = <_ModelConfigItem>[];

    for (final moduleType in ModuleType.values) {
      final modelName = config.getModel(moduleType.code);
      if (modelName != null && modelName.isNotEmpty) {
        items.add(
          _ModelConfigItem(moduleType: moduleType, modelName: modelName),
        );
      }
    }

    return items;
  }

  /// 构建单个模型项
  Widget _buildModelItem(_ModelConfigItem item, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 模块图标
          Icon(item.moduleType.icon, size: 16, color: Colors.blue.shade500),
          const SizedBox(width: 8),
          // 模块类型标签
          SizedBox(
            width: 70,
            child: Text(
              item.moduleType.label,
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
            style: TextStyle(fontSize: 13, color: isDark ? const Color(0xFFB0B0B0) : Colors.grey.shade600),
          ),
          // 模型名称
          Expanded(
            child: Text(
              item.modelName,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? const Color(0xFFE0E0E0) : Colors.black87,
                fontWeight: FontWeight.w400,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// 模型配置项
class _ModelConfigItem {
  /// 模块类型
  final ModuleType moduleType;

  /// 模型名称
  final String modelName;

  const _ModelConfigItem({required this.moduleType, required this.modelName});
}
