import 'package:flutter/material.dart';
import 'package:ai_assistant/core/models/module_info.dart';

/// 模型选择页面
///
/// 显示指定模块类型的所有可用模型，供用户选择
class ModelPickerScreen extends StatelessWidget {
  /// 模块类型
  final ModuleType moduleType;

  /// 当前选中的模型名称
  final String? currentSelection;

  /// 可用模型列表
  final List<ModuleInfo> models;

  const ModelPickerScreen({
    required this.moduleType,
    required this.models,
    super.key,
    this.currentSelection,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(
          '选择${moduleType.label}模型',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
        ),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body:
          models.isEmpty
              ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.inbox_outlined,
                      size: 64,
                      color: isDark ? const Color(0xFF3A3A3A) : Colors.grey.shade300,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '暂无可用模型',
                      style: TextStyle(
                        color: isDark ? const Color(0xFFB0B0B0) : Colors.grey.shade500,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              )
              : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: models.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final model = models[index];
                  final isSelected = model.displayName == currentSelection;
                  return _ModelTile(
                    model: model,
                    isSelected: isSelected,
                    onTap: () => Navigator.of(context).pop(model.displayName),
                  );
                },
              ),
    );
  }
}

/// 模型选项瓦片
class _ModelTile extends StatelessWidget {
  final ModuleInfo model;
  final bool isSelected;
  final VoidCallback onTap;

  const _ModelTile({
    required this.model,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color:
                  isSelected
                      ? const Color(0xFF10B981)
                      : (isDark ? const Color(0xFF3A3A3A) : const Color(0xFFE5E7EB)),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              // 模型信息 - 一行显示
              Expanded(
                child: Text(
                  model.displayName,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? const Color(0xFF10B981) : theme.colorScheme.onSurface,
                  ),
                ),
              ),
              // 选中标记
              if (isSelected)
                const Icon(
                  Icons.check_circle,
                  color: Color(0xFF10B981),
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
