import 'package:flutter/material.dart';
import 'package:ai_assistant/core/models/conversation.dart';
import 'package:ai_assistant/core/models/diy_config.dart';
import 'package:ai_assistant/core/models/dify_config.dart';
import 'package:ai_assistant/core/providers/conversation_provider.dart';
import 'package:ai_assistant/core/providers/config_provider.dart';
import 'package:ai_assistant/features/chat/screens/chat_screen.dart';
import 'package:ai_assistant/features/conversation/models/service_type_config.dart';
import 'package:ai_assistant/features/settings/screens/server_settings_screen.dart';

/// 对话类型选择状态管理
class ConversationTypeProvider extends ChangeNotifier {
  final BuildContext context;
  final ConversationProvider conversationProvider;
  final ConfigProvider configProvider;

  ConversationTypeProvider({
    required this.context,
    required this.conversationProvider,
    required this.configProvider,
  });

  // 状态变量
  ServiceTypeConfig? _selectedServiceType;
  DiyConfig? _selectedDiyConfig;
  DifyConfig? _selectedDifyConfig;

  // Getters
  ServiceTypeConfig? get selectedServiceType => _selectedServiceType;
  DiyConfig? get selectedDiyConfig => _selectedDiyConfig;
  DifyConfig? get selectedDifyConfig => _selectedDifyConfig;

  /// 是否可以创建对话
  bool get canCreateConversation {
    if (_selectedServiceType == null) {
      return false;
    }

    if (_selectedServiceType!.id == ServiceTypeConfigs.customService.id) {
      return _selectedDiyConfig != null;
    }
    if (_selectedServiceType!.id == ServiceTypeConfigs.difyService.id) {
      return _selectedDifyConfig != null;
    }

    return false;
  }

  /// 获取当前可用的配置列表
  List<dynamic> get availableConfigs {
    if (_selectedServiceType == null) {
      return [];
    }

    if (_selectedServiceType!.id == ServiceTypeConfigs.customService.id) {
      return configProvider.diyConfigs;
    }
    if (_selectedServiceType!.id == ServiceTypeConfigs.difyService.id) {
      return configProvider.difyConfigs;
    }

    return [];
  }

  /// 选择服务类型
  void selectServiceType(ServiceTypeConfig? serviceType) {
    _selectedServiceType = serviceType;

    // 清空之前选择的配置
    _selectedDiyConfig = null;
    _selectedDifyConfig = null;

    // 如果有配置可用，自动选择第一个
    if (serviceType != null) {
      _autoSelectFirstConfig(serviceType.id);
    }

    notifyListeners();
  }

  /// 自动选择第一个配置
  void _autoSelectFirstConfig(String serviceTypeId) {
    if (serviceTypeId == ServiceTypeConfigs.customService.id) {
      final configs = configProvider.diyConfigs;
      if (configs.isNotEmpty) {
        _selectedDiyConfig = configs.first;
      }
    } else if (serviceTypeId == ServiceTypeConfigs.difyService.id) {
      final configs = configProvider.difyConfigs;
      if (configs.isNotEmpty) {
        _selectedDifyConfig = configs.first;
      }
    }
  }

  /// 选择自定义配置
  void selectDiyConfig(DiyConfig? config) {
    _selectedDiyConfig = config;
    notifyListeners();
  }

  /// 选择Dify配置
  void selectDifyConfig(DifyConfig? config) {
    _selectedDifyConfig = config;
    notifyListeners();
  }

  /// 创建对话
  Future<void> createConversation() async {
    if (!canCreateConversation) {
      _showSnackBar('请先选择服务类型和配置');
      return;
    }

    if (_selectedServiceType!.id == ServiceTypeConfigs.difyService.id &&
        _selectedDifyConfig != null) {
      await _createDifyConversation(_selectedDifyConfig!);
    } else if (_selectedServiceType!.id ==
            ServiceTypeConfigs.customService.id &&
        _selectedDiyConfig != null) {
      await _createDiyConversation(_selectedDiyConfig!);
    }
  }

  /// 创建Dify对话
  Future<void> _createDifyConversation(DifyConfig config) async {
    final navigator = Navigator.of(context);

    try {
      final conversation = await conversationProvider.createConversation(
        title: '与 ${config.name} 的对话',
        type: ConversationType.dify,
        configId: config.id,
      );

      if (context.mounted) {
        navigator.pushReplacement(
          MaterialPageRoute(
            builder: (context) => ChatScreen(conversation: conversation),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        _showSnackBar('创建对话失败: ${e.toString()}');
      }
    }
  }

  /// 创建自定义对话
  Future<void> _createDiyConversation(DiyConfig config) async {
    final navigator = Navigator.of(context);

    try {
      final conversation = await conversationProvider.createConversation(
        title: '与 ${config.name} 的对话',
        type: ConversationType.diy,
        configId: config.id,
      );

      if (context.mounted) {
        navigator.pushReplacement(
          MaterialPageRoute(
            builder: (context) => ChatScreen(conversation: conversation),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        _showSnackBar('创建对话失败: ${e.toString()}');
      }
    }
  }

  /// 显示SnackBar
  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// 返回上一页
  void navigateBack() {
    Navigator.of(context).pop();
  }

  /// 显示底部选择器
  Future<void> showServiceTypeSelector() async {
    // 检查是否有任何可用配置
    final availableTypes = ServiceTypeConfigs.getAvailable(configProvider);

    if (availableTypes.isEmpty) {
      // 显示跳转提示窗口
      await _showNoConfigDialog();
      return;
    }

    // 正常显示选择器
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder:
          (context) => _ServiceTypeSelectorSheet(
            onSelected: selectServiceType,
            selectedType: _selectedServiceType,
            availableTypes: availableTypes,
          ),
    );
  }

  /// 显示无配置提示对话框
  Future<void> _showNoConfigDialog() async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.info_outline, color: Colors.orange.shade600),
            const SizedBox(width: 8),
            const Text('暂无服务配置'),
          ],
        ),
        content: const Text(
          '您还没有添加任何服务配置，请先前往服务器设置页面添加服务。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop(); // 关闭对话框
              // 跳转到服务器设置页面
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const ServerSettingsScreen(),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade600,
              foregroundColor: Colors.white,
            ),
            child: const Text('去设置'),
          ),
        ],
      ),
    );
  }

  /// 显示配置选择器
  Future<void> showConfigSelector() async {
    if (_selectedServiceType == null) {
      return;
    }

    if (_selectedServiceType!.id == ServiceTypeConfigs.customService.id) {
      await _showDiyConfigSelector();
    }
    if (_selectedServiceType!.id == ServiceTypeConfigs.difyService.id) {
      await _showDifyConfigSelector();
    }
  }

  /// 显示自定义配置选择器
  Future<void> _showDiyConfigSelector() async {
    final configs = configProvider.diyConfigs;
    if (configs.isEmpty) {
      _showSnackBar('请先在设置中添加自定义服务配置');
      return;
    }

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder:
          (context) => _ConfigSelectorSheet<DiyConfig>(
            title: '选择自定义服务配置',
            configs: configs,
            selectedConfig: _selectedDiyConfig,
            configName: (config) => config.name,
            onSelected: selectDiyConfig,
          ),
    );
  }

  /// 显示Dify配置选择器
  Future<void> _showDifyConfigSelector() async {
    final configs = configProvider.difyConfigs;
    if (configs.isEmpty) {
      _showSnackBar('请先在设置中添加Dify服务配置');
      return;
    }

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder:
          (context) => _ConfigSelectorSheet<DifyConfig>(
            title: '选择Dify服务配置',
            configs: configs,
            selectedConfig: _selectedDifyConfig,
            configName: (config) => config.name,
            onSelected: selectDifyConfig,
          ),
    );
  }
}

/// 服务类型选择器底部弹窗
class _ServiceTypeSelectorSheet extends StatelessWidget {
  final Function(ServiceTypeConfig?) onSelected;
  final ServiceTypeConfig? selectedType;
  final List<ServiceTypeConfig> availableTypes;

  const _ServiceTypeSelectorSheet({
    required this.onSelected,
    required this.availableTypes,
    this.selectedType,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题栏
            _buildHeader(context, '选择服务类型'),
            // 服务类型列表 - 使用 availableTypes
            ...availableTypes.map(
              (config) => _buildServiceTypeItem(context, config),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, String title) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceTypeItem(BuildContext context, ServiceTypeConfig config) {
    final bool isSelected = selectedType?.id == config.id;

    return InkWell(
      onTap: () {
        onSelected(config);
        Navigator.of(context).pop();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.shade50 : Colors.transparent,
        ),
        child: Row(
          children: [
            Icon(
              config.icon,
              color: isSelected ? Colors.blue.shade600 : Colors.grey.shade600,
              size: 24,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    config.displayName,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.blue.shade700 : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    config.description,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: Colors.blue.shade600, size: 24),
          ],
        ),
      ),
    );
  }
}

/// 配置选择器底部弹窗
class _ConfigSelectorSheet<T> extends StatelessWidget {
  final String title;
  final List<T> configs;
  final T? selectedConfig;
  final String Function(T) configName;
  final Function(T?) onSelected;

  const _ConfigSelectorSheet({
    required this.title,
    required this.configs,
    required this.configName,
    required this.onSelected,
    this.selectedConfig,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题栏
            _buildHeader(context, title),
            // 配置列表
            ...configs.map((config) => _buildConfigItem(context, config)),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, String title) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigItem(BuildContext context, T config) {
    final bool isSelected = selectedConfig == config;
    final String name = configName(config);

    return InkWell(
      onTap: () {
        onSelected(config);
        Navigator.of(context).pop();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.shade50 : Colors.transparent,
        ),
        child: Row(
          children: [
            Icon(
              Icons.settings,
              color: isSelected ? Colors.blue.shade600 : Colors.grey.shade600,
              size: 24,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                name,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: isSelected ? Colors.blue.shade700 : Colors.black87,
                ),
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: Colors.blue.shade600, size: 24),
          ],
        ),
      ),
    );
  }
}
