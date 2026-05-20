import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ai_assistant/core/models/diy_config.dart';
// 🔒 隐藏 Dify 服务：注释掉 Dify 配置模型导入
// import 'package:ai_assistant/core/models/dify_config.dart';
import 'package:ai_assistant/core/models/chat_service_config.dart';
import 'package:ai_assistant/core/providers/config_provider.dart';
import 'package:ai_assistant/features/settings/providers/settings_provider.dart';
import 'package:ai_assistant/features/settings/screens/add_service_screen.dart';
import 'package:ai_assistant/features/settings/screens/edit_service_screen.dart';

/// 服务器设置页面
///
/// 根据Figma设计实现：
/// - 自定义Header（非AppBar）带返回按钮和标题
/// - Section Header带标题、副标题和右侧操作按钮
/// - 支持选择模式（长按触发）、选择数量显示、全选按钮、批量删除功能
/// - 服务卡片使用圆形复选框、渐变图标、8px间距
class ServerSettingsScreen extends StatefulWidget {
  const ServerSettingsScreen({super.key});

  @override
  State<ServerSettingsScreen> createState() => _ServerSettingsScreenState();
}

class _ServerSettingsScreenState extends State<ServerSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            // 自定义Header区域
            _buildHeader(),
            // 分割线
            Container(
              height: 1,
              color: isDark ? const Color(0xFF3A3A3A) : const Color(0xFFE5E7EB),
            ),
            // 内容区域
            Expanded(child: const _ServiceListView()),
          ],
        ),
      ),
    );
  }

  /// 构建自定义Header
  Widget _buildHeader() {
    final theme = Theme.of(context);

    return Container(
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
          Text(
            '服务器设置',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

/// 添加按钮
///
/// 黑色背景，带加号图标和"添加"文字
/// 点击后导航到添加服务页面
class _AddButton extends StatelessWidget {
  const _AddButton();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => const AddServiceScreen()),
        );
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, color: theme.colorScheme.onPrimary, size: 18),
            const SizedBox(width: 4),
            Text(
              '添加',
              style: TextStyle(
                color: theme.colorScheme.onPrimary,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 服务列表视图
///
/// 包含Section Header和服务列表
class _ServiceListView extends StatelessWidget {
  const _ServiceListView();

  @override
  Widget build(BuildContext context) {
    final configProvider = context.watch<ConfigProvider>();
    final settingsProvider = context.watch<SettingsProvider>();
    final diyConfigs = configProvider.diyConfigs;
    // 🔒 隐藏 Dify 服务：注释掉 Dify 配置相关代码
    // final difyConfigs = configProvider.difyConfigs;
    // final allConfigs = [...diyConfigs, ...difyConfigs];
    final allConfigs = diyConfigs; // 只显示自定义服务配置
    final isSelectionMode = settingsProvider.isDiySelectionMode;
    // final isSelectionMode =
    //     settingsProvider.isDiySelectionMode || settingsProvider.isDifySelectionMode;

    // 计算选中数量
    // 🔒 隐藏 Dify 服务：只计算自定义服务的选中数量
    final int selectedCount = settingsProvider.selectedDiyConfigIds.length;
    // final int selectedCount = settingsProvider.isDiySelectionMode
    //     ? settingsProvider.selectedDiyConfigIds.length
    //     : settingsProvider.selectedDifyConfigIds.length;

    // 🔒 隐藏 Dify 服务：只判断自定义服务是否为空
    if (diyConfigs.isEmpty) {
      // if (diyConfigs.isEmpty && difyConfigs.isEmpty) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 64,
              color: isDark ? const Color(0xFF3A3A3A) : Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              '暂无服务配置',
              style: TextStyle(
                color: isDark ? const Color(0xFF757575) : Colors.grey.shade500,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 24),
            // 添加服务按钮
            InkWell(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const AddServiceScreen(),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.add,
                      color: Theme.of(context).colorScheme.onPrimary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '添加服务',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onPrimary,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Section Header
        _buildSectionHeader(
          context,
          isSelectionMode,
          selectedCount,
          allConfigs.length,
        ),
        // 分割线
        Container(
          height: 1,
          color:
              Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF3A3A3A)
                  : const Color(0xFFE5E7EB),
        ),
        // 服务列表
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: allConfigs.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              // 🔒 隐藏 Dify 服务：只显示自定义服务卡片
              return _ServiceCard.diy(diyConfigs[index]);
              // if (index < diyConfigs.length) {
              //   return _ServiceCard.diy(diyConfigs[index]);
              // } else {
              //   return _ServiceCard.dify(difyConfigs[index - diyConfigs.length]);
              // }
            },
          ),
        ),
      ],
    );
  }

  /// 构建Section Header
  Widget _buildSectionHeader(
    BuildContext context,
    bool isSelectionMode,
    int selectedCount,
    int totalCount,
  ) {
    final theme = Theme.of(context);
    final settingsProvider = context.watch<SettingsProvider>();
    final configProvider = context.watch<ConfigProvider>();
    final diyConfigs = configProvider.diyConfigs;
    // 🔒 隐藏 Dify 服务：注释掉 Dify 配置相关代码
    // final difyConfigs = configProvider.difyConfigs;
    // final allConfigs = [...diyConfigs, ...difyConfigs];
    final allConfigs = diyConfigs; // 只显示自定义服务配置
    // 🔒 隐藏 Dify 服务：只判断自定义服务是否全选
    final allSelected =
        settingsProvider.selectedDiyConfigIds.length == diyConfigs.length &&
        allConfigs.isNotEmpty;
    // final allSelected =
    //     settingsProvider.selectedDiyConfigIds.length == diyConfigs.length &&
    //         settingsProvider.selectedDifyConfigIds.length == difyConfigs.length &&
    //         allConfigs.isNotEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 左侧：标题和副标题
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isSelectionMode ? '选择服务 ($selectedCount)' : '自定义服务配置',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isSelectionMode ? '长按服务项可退出选择模式' : '配置并管理多个自定义WebSocket服务',
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // 右侧：操作按钮
          if (isSelectionMode)
            // 选择模式：显示全选按钮和批量删除按钮
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 全选按钮
                InkWell(
                  onTap: () {
                    // 🔒 隐藏 Dify 服务：只处理自定义服务的全选
                    settingsProvider.toggleSelectAllDiy(
                      diyConfigs.map((c) => c.id).toList(),
                    );
                    // if (settingsProvider.isDiySelectionMode) {
                    //   settingsProvider.toggleSelectAllDiy(
                    //     diyConfigs.map((c) => c.id).toList(),
                    //   );
                    // } else {
                    //   settingsProvider.toggleSelectAllDify(difyConfigs);
                    // }
                  },
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      allSelected
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      color:
                          allSelected
                              ? Colors.blue.shade600
                              : theme.colorScheme.onSurfaceVariant,
                      size: 22,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // 批量删除按钮
                InkWell(
                  onTap: () {
                    // 🔒 隐藏 Dify 服务：只处理自定义服务的批量删除
                    _confirmBatchDeleteDiy(context);
                    // if (settingsProvider.isDiySelectionMode) {
                    //   _confirmBatchDeleteDiy(context);
                    // } else {
                    //   _confirmBatchDeleteDify(context);
                    // }
                  },
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      Icons.delete_outline,
                      color: Colors.red.shade500,
                      size: 22,
                    ),
                  ),
                ),
              ],
            )
          else
            // 非选择模式：显示添加按钮
            const _AddButton(),
        ],
      ),
    );
  }

  /// 确认批量删除自定义配置
  void _confirmBatchDeleteDiy(BuildContext context) {
    final settingsProvider = context.read<SettingsProvider>();
    if (settingsProvider.selectedDiyConfigIds.isEmpty) {
      return;
    }

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text(
              '确认删除',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
            ),
            content: Text(
              '确定要删除选中的 ${settingsProvider.selectedDiyConfigIds.length} 项服务吗？此操作不可撤销。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () async {
                  final navigator = Navigator.of(context);
                  final configProvider = context.read<ConfigProvider>();
                  final scaffoldMessenger = ScaffoldMessenger.of(context);
                  final count = settingsProvider.selectedDiyConfigIds.length;

                  navigator.pop();

                  await settingsProvider.batchDeleteDiyConfigs(configProvider);

                  if (context.mounted) {
                    scaffoldMessenger.showSnackBar(
                      SnackBar(
                        content: Text('$count 项服务已删除'),
                        backgroundColor: Colors.green.shade600,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        margin: const EdgeInsets.all(10),
                      ),
                    );
                  }
                },
                child: const Text('删除', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
    );
  }

  /// 🔒 隐藏 Dify 服务：注释掉批量删除 Dify 配置的方法
  /// 确认批量删除Dify配置
  // void _confirmBatchDeleteDify(BuildContext context) {
  //   final settingsProvider = context.read<SettingsProvider>();
  //   if (settingsProvider.selectedDifyConfigIds.isEmpty) {
  //     return;
  //   }
  //
  //   showDialog(
  //     context: context,
  //     builder: (context) => AlertDialog(
  //       shape: RoundedRectangleBorder(
  //         borderRadius: BorderRadius.circular(16),
  //       ),
  //       title: const Text(
  //         '确认删除',
  //         style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
  //       ),
  //       content: Text(
  //         '确定要删除选中的 ${settingsProvider.selectedDifyConfigIds.length} 项配置吗？此操作不可撤销。',
  //       ),
  //       actions: [
  //         TextButton(
  //           onPressed: () => Navigator.of(context).pop(),
  //           child: const Text('取消'),
  //         ),
  //         TextButton(
  //           onPressed: () async {
  //             final navigator = Navigator.of(context);
  //             final configProvider = context.read<ConfigProvider>();
  //             final scaffoldMessenger = ScaffoldMessenger.of(context);
  //             final count = settingsProvider.selectedDifyConfigIds.length;
  //
  //             navigator.pop();
  //
  //             await settingsProvider.batchDeleteDifyConfigs(configProvider);
  //
  //             if (context.mounted) {
  //               scaffoldMessenger.showSnackBar(
  //                 SnackBar(
  //                   content: Text('$count 项配置已删除'),
  //                   backgroundColor: Colors.green.shade600,
  //                   behavior: SnackBarBehavior.floating,
  //                   shape: RoundedRectangleBorder(
  //                     borderRadius: BorderRadius.circular(10),
  //                   ),
  //                   margin: const EdgeInsets.all(10),
  //                 ),
  //               );
  //             }
  //           },
  //           child: const Text('删除', style: TextStyle(color: Colors.red)),
  //         ),
  //       ],
  //     ),
  //   );
  // }
}

/// 服务卡片
///
/// 根据Figma设计实现：
/// - 40x40渐变图标（自定义服务绿色）
/// 🔒 隐藏 Dify 服务：注释掉 Dify 服务图标颜色描述
/// - 40x40渐变图标（自定义服务绿色，Dify服务蓝色）
/// - 圆形复选框（选择模式下）
/// - 8px内边距，16px圆角
/// - 选中状态：蓝色边框+蓝色背景
/// - 支持自定义图标显示（从配置中读取）
class _ServiceCard extends StatelessWidget {
  final String id;
  final String name;
  final String url;
  final ServiceType type;
  final bool isDiy;
  final ServiceIcon icon;

  _ServiceCard.diy(DiyConfig config)
    : id = config.id,
      name = config.name,
      url = config.websocketUrl,
      type = ServiceType.custom,
      isDiy = true,
      icon = config.icon;

  // 🔒 隐藏 Dify 服务：注释掉 Dify 服务卡片构造函数
  // _ServiceCard.dify(DifyConfig config)
  //     : id = config.id,
  //       name = config.name,
  //       url = config.apiUrl,
  //       type = ServiceType.dify,
  //       isDiy = false,
  //       icon = config.icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final settingsProvider = context.watch<SettingsProvider>();
    // 🔒 隐藏 Dify 服务：只处理自定义服务的选中状态
    final bool isSelected =
        settingsProvider.isDiySelectionMode &&
        settingsProvider.selectedDiyConfigIds.contains(id);
    // final bool isSelected = isDiy
    //     ? (settingsProvider.isDiySelectionMode &&
    //         settingsProvider.selectedDiyConfigIds.contains(id))
    //     : (settingsProvider.isDifySelectionMode &&
    //         settingsProvider.selectedDifyConfigIds.contains(id));

    final isSelectionMode = settingsProvider.isDiySelectionMode;
    // final isSelectionMode =
    //     isDiy ? settingsProvider.isDiySelectionMode : settingsProvider.isDifySelectionMode;

    return Material(
      color:
          isSelected
              ? (isDark ? const Color(0xFF1E3A8A) : const Color(0xFFEFF6FF))
              : theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () {
          if (isSelectionMode) {
            // 🔒 隐藏 Dify 服务：只处理自定义服务的选中切换
            settingsProvider.toggleDiyConfigSelection(id);
            // if (isDiy) {
            //   settingsProvider.toggleDiyConfigSelection(id);
            // } else {
            //   settingsProvider.toggleDifyConfigSelection(id);
            // }
          } else {
            // 编辑配置
            _showEditDialog(context);
          }
        },
        onLongPress: () {
          // 🔒 隐藏 Dify 服务：只处理自定义服务的长按选择模式切换
          settingsProvider.toggleDiySelectionMode();
          // if (isDiy) {
          //   settingsProvider.toggleDiySelectionMode();
          // } else {
          //   settingsProvider.toggleDifySelectionMode();
          // }
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color:
                  isSelected
                      ? const Color(0xFF3B82F6)
                      : (isDark
                          ? const Color(0xFF3A3A3A)
                          : Colors.grey.shade300),
              width: isSelected ? 2 : 1,
            ),
            boxShadow: [
              if (!isSelected)
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
            ],
          ),
          child: Row(
            children: [
              // 选择模式复选框 或 服务图标
              if (isSelectionMode)
                _buildCheckbox(context, isSelected)
              else
                _buildIcon(),
              const SizedBox(width: 12),
              // 服务信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      url,
                      style: TextStyle(
                        fontSize: 12,
                        color:
                            isDark
                                ? const Color(0xFF757575)
                                : Colors.grey.shade500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // 删除按钮（非选择模式下显示）
              if (!isSelectionMode) _buildDeleteButton(context),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建选择模式复选框
  Widget _buildCheckbox(BuildContext context, bool isSelected) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isSelected ? const Color(0xFF3B82F6) : Colors.transparent,
        border: Border.all(
          color:
              isSelected
                  ? const Color(0xFF3B82F6)
                  : (isDark ? const Color(0xFF4A4A4A) : Colors.grey.shade300),
          width: 2,
        ),
      ),
      child:
          isSelected
              ? const Icon(Icons.check, color: Colors.white, size: 12)
              : null,
    );
  }

  /// 构建服务图标
  ///
  /// 使用配置中的自定义图标（包含图标、背景色、图标颜色）
  /// 如果没有配置图标，则使用默认的渐变背景
  Widget _buildIcon() {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: icon.backgroundColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: icon.backgroundColor.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(icon.iconData, color: icon.iconColor, size: 20),
    );
  }

  /// 构建删除按钮
  Widget _buildDeleteButton(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => _confirmDelete(context),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(
          Icons.delete_outline,
          color:
              theme.brightness == Brightness.dark
                  ? const Color(0xFFEF5350)
                  : const Color(0xFFEF4444),
          size: 18,
        ),
      ),
    );
  }

  /// 显示编辑对话框
  void _showEditDialog(BuildContext context) {
    // 🔒 隐藏 Dify 服务：只处理自定义服务的编辑
    final config = context.read<ConfigProvider>().diyConfigs.firstWhere(
      (c) => c.id == id,
      orElse: () => throw Exception('配置未找到'),
    );
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => EditServiceScreen(diyConfig: config),
      ),
    );
    // if (isDiy) {
    //   final config = context.read<ConfigProvider>().diyConfigs.firstWhere(
    //         (c) => c.id == id,
    //         orElse: () => throw Exception('配置未找到'),
    //       );
    //   Navigator.of(context).push(
    //     MaterialPageRoute(
    //       builder: (context) => EditServiceScreen(diyConfig: config),
    //     ),
    //   );
    // } else {
    //   final config = context.read<ConfigProvider>().difyConfigs.firstWhere(
    //         (c) => c.id == id,
    //         orElse: () => throw Exception('配置未找到'),
    //       );
    //   Navigator.of(context).push(
    //     MaterialPageRoute(
    //       builder: (context) => EditServiceScreen(difyConfig: config),
    //     ),
    //   );
    // }
  }

  /// 确认删除
  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text('确认删除'),
            content: Text('确定要删除 "$name" 吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () {
                  // 🔒 隐藏 Dify 服务：只处理自定义服务的删除
                  context.read<SettingsProvider>().deleteDiyConfig(
                    context.read<ConfigProvider>(),
                    id,
                  );
                  // if (isDiy) {
                  //   context.read<SettingsProvider>().deleteDiyConfig(
                  //     context.read<ConfigProvider>(),
                  //     id,
                  //   );
                  // } else {
                  //   context.read<SettingsProvider>().deleteDifyConfig(
                  //     context.read<ConfigProvider>(),
                  //     id,
                  //   );
                  // }
                  Navigator.of(context).pop();
                },
                child: const Text('删除', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
    );
  }
}

/// 服务类型枚举
enum ServiceType {
  /// 自定义服务
  custom,

  /// 🔒 隐藏 Dify 服务：注释掉 Dify 服务类型
  /// Dify服务
  // dify,
}
