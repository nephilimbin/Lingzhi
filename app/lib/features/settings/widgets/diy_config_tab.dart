import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ai_assistant/core/models/diy_config.dart';
import 'package:ai_assistant/core/providers/config_provider.dart';
import 'package:ai_assistant/features/settings/providers/settings_provider.dart';
import 'package:ai_assistant/features/settings/widgets/no_overscroll_behavior.dart';

class DiyConfigTab extends StatefulWidget {
  const DiyConfigTab({super.key});

  @override
  State<DiyConfigTab> createState() => _DiyConfigTabState();
}

class _DiyConfigTabState extends State<DiyConfigTab> {
  @override
  Widget build(BuildContext context) {
    final settingsProvider = context.watch<SettingsProvider>();
    final configProvider = context.watch<ConfigProvider>();
    final diyConfigs = configProvider.diyConfigs;

    Widget? currentActionControls;
    String currentTitle = '自定义服务配置';
    String currentSubtitle = '配置并管理多个自定义WebSocket服务';
    bool allDiySelected = diyConfigs.isNotEmpty &&
        settingsProvider.selectedDiyConfigIds.length ==
            diyConfigs.length;

    if (settingsProvider.isDiySelectionMode) {
      currentTitle =
          '选择服务 (${settingsProvider.selectedDiyConfigIds.length})';
      currentSubtitle = '长按服务项可退出选择模式';
      currentActionControls = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(
              allDiySelected
                  ? Icons.check_box_outlined
                  : Icons.check_box_outline_blank,
              color: Theme.of(context).primaryColor,
            ),
            tooltip: allDiySelected ? '取消全选' : '全选',
            onPressed: diyConfigs.isEmpty
                ? null
                : () {
                    final allConfigIds =
                        diyConfigs.map((c) => c.id).toList();
                    settingsProvider.toggleSelectAllDiy(allConfigIds);
                  },
            splashRadius: 20,
          ),
          IconButton(
            icon: Icon(
              Icons.delete_sweep_outlined,
              color: Colors.red.shade400,
            ),
            tooltip: '删除所选',
            onPressed: settingsProvider.selectedDiyConfigIds.isEmpty
                ? null
                : () => _confirmBatchDeleteDiy(context),
            splashRadius: 20,
          ),
        ],
      );
    } else {
      currentActionControls = ElevatedButton.icon(
        onPressed: () => _showAddDiyConfigDialog(context),
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
          if (diyConfigs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 30),
              child: Center(
                child: Text(
                  '暂无自定义服务',
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
              itemCount: diyConfigs.length,
              itemBuilder: (context, index) {
                return _buildDiyConfigItem(context, diyConfigs[index]);
              },
              separatorBuilder: (context, index) => Divider(
                height: 1,
                thickness: 1,
                indent: settingsProvider.isDiySelectionMode ? 0 : 56,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDiyConfigItem(BuildContext context, DiyConfig config) {
    final settingsProvider = context.read<SettingsProvider>();
    final bool isSelected = settingsProvider.isDiySelectionMode &&
        settingsProvider.selectedDiyConfigIds.contains(config.id);
    final primaryColor = Theme.of(context).primaryColor;

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: () {
          if (settingsProvider.isDiySelectionMode) {
            settingsProvider.toggleDiyConfigSelection(config.id);
          } else {
            _showEditDiyConfigDialog(context, config);
          }
        },
        onLongPress: () {
          settingsProvider.toggleDiySelectionMode();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12.0),
          child: Row(
            children: [
              if (settingsProvider.isDiySelectionMode)
                Padding(
                  padding: const EdgeInsets.only(right: 16.0, left: 4.0),
                  child: InkWell(
                    onTap: () =>
                        settingsProvider.toggleDiyConfigSelection(config.id),
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
              if (!settingsProvider.isDiySelectionMode)
                Padding(
                  padding: const EdgeInsets.only(right: 16.0, left: 16.0),
                  child: CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.green.shade50,
                    child: Icon(
                      Icons.cloud_queue,
                      color: Colors.green.shade600,
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
                      config.websocketUrl,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (!settingsProvider.isDiySelectionMode)
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
                              context
                                  .read<SettingsProvider>()
                                  .deleteDiyConfig(
                                      context.read<ConfigProvider>(), config.id);
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
              if (settingsProvider.isDiySelectionMode)
                const SizedBox(width: 48),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddDiyConfigDialog(BuildContext context) {
    final settingsProvider = context.read<SettingsProvider>();
    settingsProvider.clearDiyControllers();

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                        '添加自定义服务',
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
                    '配置一个新的自定义WebSocket服务',
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
                    controller: settingsProvider.newDiyNameController,
                    decoration: InputDecoration(
                      hintText: '例如：家庭助理',
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
                    '服务器地址',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: settingsProvider.newDiyWebsocketUrlController,
                    decoration: InputDecoration(
                      hintText: '例如：ws://192.168.1.10:8080',
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
                    'MAC地址',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: settingsProvider.newDiyMacAddressController,
                    decoration: InputDecoration(
                      hintText: '例如：00:1B:44:11:3A:B7',
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
                    'Token',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: settingsProvider.newDiyTokenController,
                    decoration: InputDecoration(
                      hintText: '例如：your-token-here',
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
                      final name = settingsProvider.newDiyNameController.text;
                      final baseUrl =
                          settingsProvider.newDiyWebsocketUrlController.text;

                      if (name.isNotEmpty && baseUrl.isNotEmpty) {
                        settingsProvider.addDiyConfig(
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

  void _showEditDiyConfigDialog(BuildContext context, DiyConfig config) {
    final settingsProvider = context.read<SettingsProvider>();
    settingsProvider.loadDiyConfigForEditing(config);

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                        '编辑自定义服务',
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
                    '编辑一个已有的自定义WebSocket服务',
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
                    controller: settingsProvider.diyNameController,
                    decoration: InputDecoration(
                      hintText: '例如：家庭助理',
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
                    '服务器地址',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: settingsProvider.diyWebsocketUrlController,
                    decoration: InputDecoration(
                      hintText: '例如：ws://192.168.1.10:8080',
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
                    'MAC地址',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: settingsProvider.diyMacAddressController,
                    decoration: InputDecoration(
                      hintText: '例如：00:1B:44:11:3A:B7',
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
                    'Token',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: settingsProvider.diyTokenController,
                    decoration: InputDecoration(
                      hintText: '例如：your-token-here',
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
                      final name = settingsProvider.diyNameController.text;
                      final baseUrl =
                          settingsProvider.diyWebsocketUrlController.text;

                      if (name.isNotEmpty && baseUrl.isNotEmpty) {
                        settingsProvider.updateDiyConfig(
                          context.read<ConfigProvider>(),
                          config,
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

  void _confirmBatchDeleteDiy(BuildContext context) {
    final settingsProvider = context.read<SettingsProvider>();
    if (settingsProvider.selectedDiyConfigIds.isEmpty) {
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        elevation: 4,
        title: const Text(
          '确认删除',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 20),
        ),
        content: ScrollConfiguration(
          behavior: NoOverscrollBehavior(),
          child: SingleChildScrollView(
            child: Text(
              '确定要删除选中的 ${settingsProvider.selectedDiyConfigIds.length} 项服务吗？此操作不可撤销。',
              style: const TextStyle(fontSize: 15),
            ),
          ),
        ),
        actionsPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              foregroundColor: Colors.grey.shade700,
              splashFactory: NoSplash.splashFactory,
            ),
            child: const Text(
              '取消',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 10,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () async {
              final navigator = Navigator.of(context); // Capture navigator
              final configProvider = context.read<ConfigProvider>();
              final scaffoldMessenger = ScaffoldMessenger.of(context);
              final count = settingsProvider.selectedDiyConfigIds.length;

              navigator.pop(); // Close the confirmation dialog

              await settingsProvider.batchDeleteDiyConfigs(configProvider);

              if (mounted) {
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
            child: const Text(
              '删除',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
