import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ai_assistant/core/models/diy_config.dart';
import 'package:ai_assistant/core/models/server_model_config.dart';
import 'package:ai_assistant/core/models/module_info.dart';
import 'package:ai_assistant/core/providers/config_provider.dart';
import 'package:ai_assistant/core/api/modules_api.dart';
import 'package:ai_assistant/core/services/modules_cache_service.dart';
import 'package:ai_assistant/features/settings/screens/model_picker_screen.dart';

/// 模型设置页面
///
/// 允许用户为每个已配置的服务器独立选择AI模型
/// 流程：
/// 1. 显示已配置的服务器列表
/// 2. 选择服务器后显示模块类型列表
/// 3. 选择模块类型后显示可用模型列表
class ModelSettingsScreen extends StatefulWidget {
  const ModelSettingsScreen({super.key});

  @override
  State<ModelSettingsScreen> createState() => _ModelSettingsScreenState();
}

class _ModelSettingsScreenState extends State<ModelSettingsScreen> {
  /// 当前选中的服务器ID，null表示显示服务器列表
  String? _selectedServerId;

  /// 是否正在加载
  bool _isLoading = false;

  /// 跟踪已加载的服务器，避免重复刷新
  /// 当用户第一次选择某个服务器时，会自动加载模块列表
  /// 后续再次选择该服务器时，不会自动刷新，除非用户手动刷新
  final Set<String> _loadedServers = {};

  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(ModelSettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Divider(height: 1, color: theme.brightness == Brightness.dark ? const Color(0xFF3A3A3A) : const Color(0xFFE5E7EB)),
            Expanded(
              child:
                  _selectedServerId == null
                      ? _buildServerList()
                      : _buildModuleList(),
            ),
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
          // 返回/关闭按钮
          InkWell(
            onTap: () {
              if (_selectedServerId != null) {
                setState(() => _selectedServerId = null);
              } else {
                Navigator.of(context).pop();
              }
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.all(8),
              child: Icon(
                _selectedServerId == null ? Icons.arrow_back : Icons.close,
                color: theme.colorScheme.onSurface,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // 标题
          Text(
            _selectedServerId == null ? '选择服务器' : '配置模型',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  /// 处理服务器选择
  ///
  /// 当用户选择服务器时调用该方法。如果这是第一次选择该服务器，
  /// 则自动加载模块列表并进行验证。后续选择不会自动刷新。
  ///
  /// [serverId] 选中的服务器ID
  void _onServerSelected(String serverId) {
    setState(() => _selectedServerId = serverId);

    // 只在第一次选择该服务器时自动加载
    if (!_loadedServers.contains(serverId)) {
      _loadedServers.add(serverId);
      _loadModulesAndValidate();
    }
  }

  /// 刷新模块列表
  Future<void> _refreshModules() async {
    if (_selectedServerId == null) {
      return;
    }

    setState(() => _isLoading = true);

    final configProvider = context.read<ConfigProvider>();
    final server = configProvider.diyConfigs.firstWhere(
      (s) => s.id == _selectedServerId,
    );

    try {
      // 清除缓存并从后端重新获取
      await ModulesCacheService.clearCache(_selectedServerId!);
      final response = await ModulesApi.fetchModules(server.websocketUrl);

      // 缓存时使用 response.modules
      await ModulesCacheService.cacheModules(
        _selectedServerId!,
        response.modules,
      );

      // 验证并更新模型配置
      await _validateAndUpdateModelConfigs(response);

      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('模型列表已刷新'),
            backgroundColor: Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(10)),
            ),
            margin: EdgeInsets.all(16),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('刷新失败: $e'),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    }
  }

  /// 加载模块并验证模型配置
  Future<void> _loadModulesAndValidate() async {
    if (_selectedServerId == null) {
      return;
    }

    await _refreshModules();
  }

  /// 验证并更新模型配置
  ///
  /// 根据 [response.defaultSelectedModule] 验证当前配置的模型是否仍然有效
  /// 如果配置的模型不再可用，则使用默认配置更新
  ///
  /// 处理所有模块类型：VAD, ASR, LLM, TTS, Memory, Intent, VLM
  Future<void> _validateAndUpdateModelConfigs(ModulesResponse response) async {
    final configProvider = context.read<ConfigProvider>();
    ServerModelConfig? modelConfig = configProvider.getModelConfig(
      _selectedServerId!,
    );

    // 如果没有现有配置，使用默认配置初始化
    if (modelConfig == null) {
      await _initializeDefaultConfig(response);
      return;
    }

    // 创建新的配置映射
    final updatedModels = <String, String?>{};
    bool hasChanges = false;

    // 遍历所有模块类型，确保每种类型都被处理
    for (final moduleType in ModuleType.values) {
      final moduleCode = moduleType.code;
      final currentSelection = modelConfig.getModel(moduleCode);

      // 获取该类型的可用模型列表
      final availableModels = response.modules[moduleCode];

      if (currentSelection == null || currentSelection.isEmpty) {
        // 当前未配置，使用默认值
        final defaultModel = response.defaultSelectedModule[moduleCode];
        if (defaultModel != null && defaultModel.isNotEmpty) {
          updatedModels[moduleCode] = defaultModel;
          // 只有当之前没有配置而现在有默认配置时才算变化
          if (modelConfig.selectedModels[moduleCode] != defaultModel) {
            hasChanges = true;
          }
        } else {
          // 没有默认值且当前未配置，保持未配置状态
          updatedModels[moduleCode] = null;
        }
        continue;
      }

      // 检查当前选中的模型是否仍在可用列表中
      if (availableModels == null || availableModels.isEmpty) {
        // 该类型没有可用模型，使用默认配置（如果有）
        final defaultModel = response.defaultSelectedModule[moduleCode];
        updatedModels[moduleCode] =
            defaultModel?.isNotEmpty == true ? defaultModel : null;
        if (updatedModels[moduleCode] != currentSelection) {
          hasChanges = true;
        }
        continue;
      }

      // 检查当前选中的模型是否在可用列表中
      final modelExists = availableModels.any(
        (m) => m.name == currentSelection,
      );
      if (!modelExists) {
        // 模型不再可用，使用默认配置
        final defaultModel = response.defaultSelectedModule[moduleCode];
        updatedModels[moduleCode] =
            defaultModel?.isNotEmpty == true ? defaultModel : null;
        if (updatedModels[moduleCode] != currentSelection) {
          hasChanges = true;
        }
      } else {
        // 模型仍然可用，保持原配置
        updatedModels[moduleCode] = currentSelection;
      }
    }

    // 只有当配置有变化时才更新
    if (hasChanges) {
      final updatedConfig = ServerModelConfig(
        serverId: _selectedServerId!,
        selectedModels: updatedModels,
      );
      await configProvider.updateModelConfig(updatedConfig);

      // 调试日志
      if (mounted) {
        _logConfigUpdate(updatedModels);
      }
    }
  }

  /// 使用默认配置初始化模型配置
  ///
  /// 为所有模块类型设置服务器的默认配置
  /// 如果某个模块类型没有默认配置，则保持未配置状态
  Future<void> _initializeDefaultConfig(ModulesResponse response) async {
    final configProvider = context.read<ConfigProvider>();

    // 从响应的默认配置创建初始配置
    final initialModels = <String, String?>{};

    // 遍历所有模块类型
    for (final moduleType in ModuleType.values) {
      final moduleCode = moduleType.code;
      final defaultModel = response.defaultSelectedModule[moduleCode];

      // 只有当默认配置存在且不为空时才设置
      if (defaultModel != null && defaultModel.isNotEmpty) {
        initialModels[moduleCode] = defaultModel;
      } else {
        // 没有默认配置的模块类型保持未配置状态
        initialModels[moduleCode] = null;
      }
    }

    // 创建并保存配置
    final defaultConfig = ServerModelConfig(
      serverId: _selectedServerId!,
      selectedModels: initialModels,
    );

    await configProvider.updateModelConfig(defaultConfig);

    // 调试日志
    if (mounted) {
      _logConfigInitialization(initialModels);
    }
  }

  /// 记录配置初始化的日志
  void _logConfigInitialization(Map<String, String?> models) {
    final buffer = StringBuffer();
    buffer.writeln('【模型配置】使用默认配置初始化服务器: $_selectedServerId');
    for (final entry in models.entries) {
      if (entry.value != null) {
        buffer.writeln('  ${entry.key}: ${entry.value}');
      }
    }
    // 使用开发者日志输出
    debugPrint(buffer.toString().trim());
  }

  /// 记录配置更新的日志
  void _logConfigUpdate(Map<String, String?> models) {
    final buffer = StringBuffer();
    buffer.writeln('【模型配置】更新服务器配置: $_selectedServerId');
    for (final entry in models.entries) {
      buffer.writeln('  ${entry.key}: ${entry.value ?? "未配置"}');
    }
    debugPrint(buffer.toString().trim());
  }

  /// 构建服务器列表
  Widget _buildServerList() {
    final configProvider = context.watch<ConfigProvider>();
    final servers = configProvider.diyConfigs;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (servers.isEmpty) {
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
              '暂无服务器配置',
              style: TextStyle(color: isDark ? const Color(0xFFB0B0B0) : Colors.grey.shade500, fontSize: 15),
            ),
            const SizedBox(height: 8),
            Text(
              '请先添加服务器',
              style: TextStyle(color: isDark ? const Color(0xFF757575) : Colors.grey.shade400, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: servers.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final server = servers[index];
        return _ServerConfigCard(
          server: server,
          onTap: () => _onServerSelected(server.id),
        );
      },
    );
  }

  /// 构建模块类型列表
  Widget _buildModuleList() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: ModuleType.values.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final moduleType = ModuleType.values[index];
        return _ModuleTypeCard(
          serverId: _selectedServerId!,
          moduleType: moduleType,
        );
      },
    );
  }
}

/// 服务器配置卡片
class _ServerConfigCard extends StatelessWidget {
  final DiyConfig server;
  final VoidCallback onTap;

  const _ServerConfigCard({required this.server, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final configProvider = context.watch<ConfigProvider>();
    final modelConfig = configProvider.getModelConfig(server.id);
    final configuredCount =
        modelConfig?.selectedModels.values.where((v) => v != null).length ?? 0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? const Color(0xFF3A3A3A) : Colors.grey.shade200,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              // 服务图标
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: server.icon.backgroundColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  server.icon.iconData,
                  color: server.icon.iconColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              // 服务信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      server.name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '已配置 $configuredCount 个模型',
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? const Color(0xFFB0B0B0) : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              // 右箭头
              Icon(Icons.chevron_right, color: isDark ? const Color(0xFF757575) : Colors.grey.shade400, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

/// 模块类型卡片
class _ModuleTypeCard extends StatelessWidget {
  final String serverId;
  final ModuleType moduleType;

  const _ModuleTypeCard({required this.serverId, required this.moduleType});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final configProvider = context.watch<ConfigProvider>();
    final modelConfig = configProvider.getModelConfig(serverId);
    final selectedModel = modelConfig?.getModel(moduleType.code);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _selectModel(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? const Color(0xFF3A3A3A) : Colors.grey.shade200,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              // 模块图标
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  moduleType.icon,
                  color: const Color(0xFF10B981),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              // 模块信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      moduleType.label,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      selectedModel ?? '未配置',
                      style: TextStyle(
                        fontSize: 14,
                        color:
                            selectedModel != null
                                ? (isDark ? const Color(0xFFB0B0B0) : Colors.grey.shade600)
                                : Colors.grey.shade400,
                      ),
                    ),
                  ],
                ),
              ),
              // 右箭头
              Icon(Icons.chevron_right, color: isDark ? const Color(0xFF757575) : Colors.grey.shade400, size: 22),
            ],
          ),
        ),
      ),
    );
  }

  /// 选择模型
  Future<void> _selectModel(BuildContext context) async {
    final configProvider = context.read<ConfigProvider>();
    final server = configProvider.diyConfigs.firstWhere(
      (s) => s.id == serverId,
    );

    // 先尝试从缓存获取
    var cachedModules = await ModulesCacheService.getCachedModules(serverId);

    // 从API获取完整的响应数据
    ModulesResponse response;

    if (cachedModules == null) {
      // 缓存无效，从后端获取完整响应
      try {
        response = await ModulesApi.fetchModules(server.websocketUrl);
        // 缓存时使用 response.modules
        await ModulesCacheService.cacheModules(serverId, response.modules);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('获取模型列表失败: $e'),
              backgroundColor: Colors.red.shade600,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              margin: const EdgeInsets.all(16),
            ),
          );
        }
        return;
      }
    } else {
      // 有缓存，需要获取完整响应（包含默认配置）
      try {
        response = await ModulesApi.fetchModules(server.websocketUrl);
        // 更新缓存
        await ModulesCacheService.cacheModules(serverId, response.modules);
      } catch (e) {
        // 网络请求失败，使用缓存数据创建临时响应
        response = ModulesResponse(
          modules: cachedModules,
          defaultSelectedModule: const {},
        );
      }
    }

    if (!context.mounted) {
      return;
    }

    // 从 response.modules 中获取可用模型列表
    final availableModels = response.modules[moduleType.code] ?? [];

    final selected = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder:
            (context) => ModelPickerScreen(
              moduleType: moduleType,
              models: availableModels,
              currentSelection: configProvider
                  .getModelConfig(serverId)
                  ?.getModel(moduleType.code),
            ),
      ),
    );

    if (selected != null) {
      // 从 displayName 中提取 name 部分（一级名称）
      // displayName 格式为 "name:modelName"（如 "QwenASR:gummy-realtime-v1"）
      // 我们只需要存储 name 部分（如 "QwenASR"）
      final modelName = selected.split(':').first;

      var currentConfig = configProvider.getModelConfig(serverId);
      currentConfig ??= ServerModelConfig(
        serverId: serverId,
        selectedModels: {},
      );
      await configProvider.updateModelConfig(
        currentConfig.setModel(moduleType.code, modelName),
      );
    }
  }
}
