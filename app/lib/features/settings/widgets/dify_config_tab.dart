import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ai_assistant/core/models/dify_config.dart';
import 'package:ai_assistant/core/providers/config_provider.dart';
import 'package:ai_assistant/features/settings/providers/settings_provider.dart';
import 'package:ai_assistant/features/settings/widgets/no_overscroll_behavior.dart';

class DifyConfigTab extends StatefulWidget {
  const DifyConfigTab({super.key});

  @override
  State<DifyConfigTab> createState() => _DifyConfigTabState();
}

class _DifyConfigTabState extends State<DifyConfigTab> {
  @override
  Widget build(BuildContext context) {
    final settingsProvider = context.watch<SettingsProvider>();
    final configProvider = context.watch<ConfigProvider>();
    final difyConfigs = configProvider.difyConfigs;

    Widget? currentActionControls;
    String currentTitle = 'Dify API配置';
    String currentSubtitle = '配置并管理多个Dify API服务';
    bool allDifySelected =
        difyConfigs.isNotEmpty &&
        settingsProvider.selectedDifyConfigIds.length == difyConfigs.length;

    if (settingsProvider.isDifySelectionMode) {
      currentTitle = '选择Dify配置 (${settingsProvider.selectedDifyConfigIds.length})';
      currentSubtitle = '长按服务项可退出选择模式';
      currentActionControls = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(
              allDifySelected
                  ? Icons.check_box_outlined
                  : Icons.check_box_outline_blank,
              color: Theme.of(context).primaryColor,
            ),
            tooltip: allDifySelected ? '取消全选' : '全选',
            onPressed: difyConfigs.isEmpty
                ? null
                : () => settingsProvider.toggleSelectAllDify(difyConfigs),
            splashRadius: 20,
          ),
          IconButton(
            icon: Icon(
              Icons.delete_sweep_outlined,
              color: Colors.red.shade400,
            ),
            tooltip: '删除所选',
            onPressed:
                settingsProvider.selectedDifyConfigIds.isEmpty
                    ? null
                    : () => _confirmBatchDeleteDify(context),
            splashRadius: 20,
          ),
        ],
      );
    } else {
      currentActionControls = ElevatedButton.icon(
        onPressed: () => _showAddDifyDialog(context),
        icon: const Icon(Icons.add, color: Colors.white, size: 18),
        label: const Text(
          '添加',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          elevation: 0,
          minimumSize: const Size(80, 36),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      currentTitle,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      currentSubtitle,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              currentActionControls,
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, thickness: 1),
          const SizedBox(height: 10),
          if (difyConfigs.isEmpty && !settingsProvider.isDifySelectionMode)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 30),
              child: Center(
                child: Text(
                  '暂无Dify配置',
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 15,
                  ),
                ),
              ),
            )
          else if (difyConfigs.isEmpty && settingsProvider.isDifySelectionMode)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 30),
              child: Center(
                child: Text(
                  '暂无Dify配置可选择',
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 15,
                  ),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: difyConfigs.length,
              itemBuilder: (context, index) {
                return _buildDifyConfigItem(context, difyConfigs[index]);
              },
              separatorBuilder:
                  (context, index) => Divider(
                    height: 1,
                    thickness: 1,
                    indent: settingsProvider.isDifySelectionMode ? 0 : 56,
                  ),
            ),
        ],
      ),
    );
  }

  Widget _buildDifyConfigItem(BuildContext context, DifyConfig config) {
    final settingsProvider = context.read<SettingsProvider>();
    final bool isSelected =
        settingsProvider.isDifySelectionMode &&
        settingsProvider.selectedDifyConfigIds.contains(config.id);
    final primaryColor = Theme.of(context).primaryColor;

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: () {
          if (settingsProvider.isDifySelectionMode) {
            settingsProvider.toggleDifyConfigSelection(config.id);
          } else {
            _showEditDifyDialog(context, config);
          }
        },
        onLongPress: () {
          settingsProvider.toggleDifySelectionMode();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12.0),
          child: Row(
            children: [
              if (settingsProvider.isDifySelectionMode)
                Padding(
                  padding: const EdgeInsets.only(right: 16.0, left: 4.0),
                  child: InkWell(
                    onTap: () => settingsProvider.toggleDifyConfigSelection(config.id),
                    customBorder: const CircleBorder(),
                    child: Icon(
                      isSelected
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      color: isSelected ? primaryColor : Colors.grey.shade400,
                      size: 24,
                    ),
                  ),
                ),
              if (!settingsProvider.isDifySelectionMode)
                Padding(
                  padding: const EdgeInsets.only(right: 16.0, left: 16.0),
                  child: CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.blue.shade50,
                    child: Icon(
                      Icons.api,
                      color: Colors.blue.shade600,
                      size: 22,
                    ),
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      config.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      config.apiUrl,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (!settingsProvider.isDifySelectionMode)
                IconButton(
                  icon: Icon(
                    Icons.delete_outline,
                    color: Colors.red.shade400,
                    size: 22,
                  ),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: const Text('确认删除'),
                        content: Text('确定要删除 "${config.name}" 吗？'),
                        actions: [
                          TextButton(
                            child: const Text('取消'),
                            onPressed: () => Navigator.of(dialogContext).pop(),
                          ),
                          TextButton(
                            child: const Text('删除'),
                            onPressed: () {
                              context.read<SettingsProvider>().deleteDifyConfig(context.read<ConfigProvider>(), config.id);
                              Navigator.of(dialogContext).pop();
                            },
                          ),
                        ],
                      ),
                    );
                  },
                  padding: const EdgeInsets.all(8),
                  tooltip: '删除',
                  splashRadius: 20,
                ),
              if (settingsProvider.isDifySelectionMode)
                const SizedBox(width: 48), 
            ],
          ),
        ),
      ),
    );
  }

  void _confirmBatchDeleteDify(BuildContext context) {
    final settingsProvider = context.read<SettingsProvider>();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('批量删除确认'),
        content: Text(
            '确定要删除所选的 ${settingsProvider.selectedDifyConfigIds.length} 个配置吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              try {
                await settingsProvider.batchDeleteDifyConfigs(context.read<ConfigProvider>());
                if (!mounted) {
                  return;
                }
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('所选配置已删除')),
                );
              } catch (e) {
                if (!mounted) {
                  return;
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('删除失败: $e')),
                );
              }
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showAddDifyDialog(BuildContext context) {
    final settingsProvider = context.read<SettingsProvider>();
    settingsProvider.clearDifyControllers();

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        elevation: 4,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: ScrollConfiguration(
            behavior: NoOverscrollBehavior(),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '添加Dify配置',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 22),
                        onPressed: () => Navigator.pop(context),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        splashRadius: 20,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '添加新的Dify API配置',
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    '配置名称',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: settingsProvider.newDifyNameController,
                    decoration: InputDecoration(
                      hintText: '输入配置名称',
                      hintStyle: TextStyle(color: Colors.grey.shade400),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: Theme.of(context).primaryColor,
                          width: 1.5,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'API URL',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: settingsProvider.newDifyApiUrlController,
                    decoration: InputDecoration(
                      hintText: 'https://api.dify.ai/v1',
                      hintStyle: TextStyle(color: Colors.grey.shade400),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: Theme.of(context).primaryColor,
                          width: 1.5,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'API Key',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: settingsProvider.newDifyApiKeyController,
                    decoration: InputDecoration(
                      hintText: '输入API Key',
                      hintStyle: TextStyle(color: Colors.grey.shade400),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: Theme.of(context).primaryColor,
                          width: 1.5,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () {
                      final name = settingsProvider.newDifyNameController.text;
                      final apiUrl = settingsProvider.newDifyApiUrlController.text;
                      final apiKey = settingsProvider.newDifyApiKeyController.text;

                      if (name.isNotEmpty && apiUrl.isNotEmpty && apiKey.isNotEmpty) {
                        settingsProvider.addDifyConfig(
                          context.read<ConfigProvider>(),
                        );
                        Navigator.pop(context);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('添加'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showEditDifyDialog(BuildContext context, DifyConfig config) {
    final settingsProvider = context.read<SettingsProvider>();
    settingsProvider.loadDifyConfigForEditing(config);

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        elevation: 4,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: ScrollConfiguration(
            behavior: NoOverscrollBehavior(),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '编辑Dify配置',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 22),
                        onPressed: () => Navigator.pop(context),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        splashRadius: 20,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '编辑Dify API配置',
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    '配置名称',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: settingsProvider.editDifyNameController,
                    decoration: InputDecoration(
                      hintText: '输入配置名称',
                      hintStyle: TextStyle(color: Colors.grey.shade400),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: Theme.of(context).primaryColor,
                          width: 1.5,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'API URL',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: settingsProvider.editDifyApiUrlController,
                    decoration: InputDecoration(
                      hintText: 'https://api.dify.ai/v1',
                      hintStyle: TextStyle(color: Colors.grey.shade400),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: Theme.of(context).primaryColor,
                          width: 1.5,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'API Key',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: settingsProvider.editDifyApiKeyController,
                    decoration: InputDecoration(
                      hintText: '输入API Key',
                      hintStyle: TextStyle(color: Colors.grey.shade400),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: Theme.of(context).primaryColor,
                          width: 1.5,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () {
                      final name = settingsProvider.editDifyNameController.text;
                      final apiUrl = settingsProvider.editDifyApiUrlController.text;
                      final apiKey = settingsProvider.editDifyApiKeyController.text;

                      if (name.isNotEmpty && apiUrl.isNotEmpty && apiKey.isNotEmpty) {
                        settingsProvider.updateDifyConfig(
                          context.read<ConfigProvider>(),
                          config.id,
                        );
                        Navigator.pop(context);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('保存'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
