import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ai_assistant/core/models/module_info.dart';
import 'package:ai_assistant/core/models/module_info.dart' as mi;
import 'package:ai_assistant/core/models/session_model_config.dart';
import 'package:ai_assistant/core/providers/config_provider.dart';
import 'package:ai_assistant/core/providers/conversation_provider.dart';
import 'package:ai_assistant/core/providers/diy_service_provider.dart';
import 'package:ai_assistant/core/api/modules_api.dart';
import 'package:ai_assistant/core/services/modules_cache_service.dart';
import 'package:ai_assistant/core/utils/app_logger.dart';

/// 会话模型设置页面
///
/// 用于为单个对话（session）配置AI模型
/// 初始数据从 settings 的 ServerModelConfig 读取
/// 保存到 SessionModelConfig，不影响 settings 的 ServerModelConfig
class SessionModelSettingsScreen extends StatefulWidget {
  /// 对话ID
  final String conversationId;

  /// 当前会话模型配置
  final SessionModelConfig? sessionConfig;

  /// 关联的服务器配置ID
  final String configId;

  const SessionModelSettingsScreen({
    required this.conversationId,
    required this.configId,
    super.key,
    this.sessionConfig,
  });

  @override
  State<SessionModelSettingsScreen> createState() => _SessionModelSettingsScreenState();
}

class _SessionModelSettingsScreenState extends State<SessionModelSettingsScreen> {
  /// 当前选中的模块类型，null表示显示模块列表
  mi.ModuleType? _selectedModuleType;

  /// 从后端获取的模块数据
  Map<String, List<ModuleInfo>> _modulesMap = {};

  /// 是否正在加载
  bool _isLoading = false;

  /// 是否已经加载过数据（防止每次页面激活都自动刷新）
  bool _hasLoaded = false;

  @override
  void initState() {
    super.initState();
    _validateAndCleanSessionConfig();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    /// 只在第一次进入页面时自动刷新模块列表并验证配置
    /// 避免后续页面激活时覆盖用户的手动修改
    ///
    /// 通过调度帧后执行，确保在页面完全加载后触发
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_hasLoaded) {
        _hasLoaded = true;
        _loadModulesAndValidate();
      }
    });
  }

  /// 加载模块并验证会话配置
  ///
  /// 每次进入页面时自动调用，清除旧缓存并强制从网络获取最新数据
  Future<void> _loadModulesAndValidate() async {
    setState(() => _isLoading = true);

    try {
      final configProvider = context.read<ConfigProvider>();
      final server = configProvider.diyConfigs.firstWhere(
        (s) => s.id == widget.configId,
      );

      // 清除旧缓存，强制从网络获取最新数据
      await ModulesCacheService.clearCache(widget.configId);

      // 从后端获取最新的模块列表
      final response = await ModulesApi.fetchModules(server.websocketUrl);

      // 缓存新的模块数据
      await ModulesCacheService.cacheModules(widget.configId, response.modules);

      // 更新UI中的模块列表
      if (mounted) {
        setState(() {
          _modulesMap = response.modules;
          _isLoading = false;
        });
      }

      // 验证并清理会话配置
      await _validateAndCleanSessionConfig(response);
    } catch (e) {
      logE('加载模块数据失败: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('加载模型列表失败: $e'),
            backgroundColor: Colors.red.shade600,
          ),
        );
      }
    }
  }

  /// 验证并清理会话模型配置
  ///
  /// 清除旧缓存，强制从网络获取最新数据
  /// 验证当前配置的模型是否在新列表中存在
  /// 不存在则使用系统默认值或服务器配置
  ///
  /// [response] 可选的模块响应对象，如果为null则从网络获取
  Future<void> _validateAndCleanSessionConfig([ModulesResponse? response]) async {
    try {
      final configProvider = context.read<ConfigProvider>();
      final server = configProvider.diyConfigs.firstWhere(
        (s) => s.id == widget.configId,
      );

      // 如果没有提供response，则从网络获取
      if (response == null) {
        // 清除旧缓存，强制从网络获取最新数据
        await ModulesCacheService.clearCache(widget.configId);

        // 从后端获取最新的模块列表
        final fetchedResponse = await ModulesApi.fetchModules(server.websocketUrl);

        // 缓存新的模块数据
        await ModulesCacheService.cacheModules(widget.configId, fetchedResponse.modules);

        // 更新UI中的模块列表
        if (mounted) {
          setState(() {
            _modulesMap = fetchedResponse.modules;
          });
        }

        // 递归调用，使用获取到的响应
        await _validateAndCleanSessionConfig(fetchedResponse);
        return;
      }

      // 获取服务器配置作为回退选项
      final serverModelConfig = configProvider.getModelConfig(widget.configId);

      // 如果没有会话配置，直接返回（无需验证）
      if (widget.sessionConfig == null) {
        return;
      }

      // 验证当前配置的模型是否在新列表中存在
      final currentConfig = widget.sessionConfig!;
      final validatedModels = <String, String?>{};
      bool hasInvalidModel = false;

      for (final moduleType in mi.ModuleType.values) {
        final moduleCode = moduleType.code;
        final currentModel = currentConfig.getModel(moduleCode);

        if (currentModel != null && currentModel.isNotEmpty) {
          // 检查该模型是否在新的模块列表中存在
          final availableModels = response.modules[moduleCode] ?? [];
          final modelExists = availableModels.any((m) => m.name == currentModel);

          if (!modelExists) {
            // 模型不存在，需要处理
            hasInvalidModel = true;
            logW('模型 $currentModel ($moduleCode) 不在新的模块列表中');

            // 优先使用系统默认值
            final defaultModel = response.defaultSelectedModule[moduleCode];
            if (defaultModel != null && defaultModel.isNotEmpty) {
              validatedModels[moduleCode] = defaultModel;
              logI('使用系统默认值: $defaultModel');
            } else {
              // 其次使用服务器配置
              final serverModel = serverModelConfig?.getModel(moduleCode);
              if (serverModel != null && serverModel.isNotEmpty) {
                validatedModels[moduleCode] = serverModel;
                logI('使用服务器配置: $serverModel');
              } else {
                // 都没有则设置为null，使用服务器默认
                validatedModels[moduleCode] = null;
                logI('设置为null，将使用服务器默认配置');
              }
            }
          } else {
            // 模型存在，保留配置
            validatedModels[moduleCode] = currentModel;
          }
        } else {
          // 当前未配置，保持未配置状态（使用服务器默认）
          validatedModels[moduleCode] = null;
        }
      }

      // 如果有无效的模型配置，更新会话配置
      if (hasInvalidModel && mounted) {
        final conversationProvider = context.read<ConversationProvider>();
        final newConfig = SessionModelConfig(
          serverId: widget.configId,
          selectedModels: validatedModels,
        );

        await conversationProvider.updateConversationSessionModelConfig(
          widget.conversationId,
          newConfig,
        );

        logI('已清理无效的模型配置');

        // 显示提示信息
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('部分模型配置已更新为服务器默认配置'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      logE('验证模型配置失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Container(
              height: 1,
              color: isDark ? const Color(0xFF3A3A3A) : const Color(0xFFE5E7EB),
            ),
            Expanded(
              child: _isLoading
                  ? _buildLoadingState()
                  : _selectedModuleType == null
                      ? _buildModuleList()
                      : _buildModelPicker(),
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
              if (_selectedModuleType != null) {
                setState(() => _selectedModuleType = null);
              } else {
                Navigator.of(context).pop();
              }
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.all(8),
              child: Icon(
                _selectedModuleType == null ? Icons.arrow_back : Icons.close,
                color: theme.colorScheme.onSurface,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // 标题
          Text(
            _selectedModuleType == null ? '会话模型配置' : '选择${_selectedModuleType!.label}模型',
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

  /// 构建加载状态
  Widget _buildLoadingState() {
    return const Center(
      child: CircularProgressIndicator(
        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
      ),
    );
  }

  /// 构建模块类型列表
  Widget _buildModuleList() {
    final configProvider = context.watch<ConfigProvider>();
    final serverModelConfig = configProvider.getModelConfig(widget.configId);

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: mi.ModuleType.values.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final moduleType = mi.ModuleType.values[index];
        final serverModel = serverModelConfig?.getModel(moduleType.code);
        final sessionModel = widget.sessionConfig?.getModel(moduleType.code);

        return _ModuleTypeCard(
          moduleType: moduleType,
          serverModel: serverModel,
          sessionModel: sessionModel,
          hasAvailableModels: _modulesMap[moduleType.code]?.isNotEmpty ?? false,
          onTap: () => setState(() => _selectedModuleType = moduleType),
        );
      },
    );
  }

  /// 构建模型选择器
  Widget _buildModelPicker() {
    final availableModels = _modulesMap[_selectedModuleType!.code] ?? [];
    final currentSelection = widget.sessionConfig?.getModel(_selectedModuleType!.code);

    return Column(
      children: [
        // 使用服务器默认配置选项
        _buildUseDefaultOption(),
        // 模型列表
        Expanded(
          child: availableModels.isEmpty
              ? _buildEmptyState()
              : _buildModelList(availableModels, currentSelection),
        ),
      ],
    );
  }

  /// 构建使用服务器默认配置选项
  Widget _buildUseDefaultOption() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final configProvider = context.watch<ConfigProvider>();
    final serverModelConfig = configProvider.getModelConfig(widget.configId);
    final serverDefaultModel = serverModelConfig?.getModel(_selectedModuleType!.code);
    final isUsingDefault = widget.sessionConfig?.getModel(_selectedModuleType!.code) == null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _selectModel(null),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: isUsingDefault
                ? (isDark ? const Color(0xFF1E3A8A).withValues(alpha: 0.3) : const Color(0xFFF0FDF4))
                : (isDark ? const Color(0xFF1E1E1E) : Colors.white),
            border: Border(
              bottom: BorderSide(
                color: isDark ? const Color(0xFF3A3A3A) : const Color(0xFFE5E7EB),
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.settings_suggest_outlined,
                size: 20,
                color: isUsingDefault
                    ? const Color(0xFF10B981)
                    : (isDark ? const Color(0xFF757575) : Colors.grey.shade600),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '使用服务器默认配置',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: isUsingDefault
                            ? const Color(0xFF10B981)
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (serverDefaultModel != null)
                      Text(
                        '服务器默认: $serverDefaultModel',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? const Color(0xFFB0B0B0) : Colors.grey.shade600,
                        ),
                      )
                    else
                      Text(
                        '跟随服务器全局设置',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? const Color(0xFF757575) : Colors.grey.shade500,
                        ),
                      ),
                  ],
                ),
              ),
              if (isUsingDefault)
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

  /// 构建空状态
  Widget _buildEmptyState() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
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
              color: isDark ? const Color(0xFF757575) : Colors.grey.shade500,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建模型列表
  Widget _buildModelList(List<ModuleInfo> models, String? currentSelection) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: models.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final model = models[index];
        final isSelected = model.name == currentSelection;
        return _ModelTile(
          model: model,
          isSelected: isSelected,
          onTap: () => _selectModel(model.name),
        );
      },
    );
  }

  /// 选择模型
  Future<void> _selectModel(String? modelName) async {
    final conversationProvider = context.read<ConversationProvider>();

    try {
      // 获取当前对话
      final conversation = conversationProvider.getConversationById(widget.conversationId);
      if (conversation == null) {
        throw Exception('对话不存在');
      }

      // 更新sessionModelConfig
      final newSessionConfig = (widget.sessionConfig ?? SessionModelConfig.empty(widget.configId))
          .setModel(_selectedModuleType!.code, modelName);

      // 更新对话
      await conversationProvider.updateConversationSessionModelConfig(
        widget.conversationId,
        newSessionConfig,
      );

      // 向后端发送配置更新请求
      await _sendConfigUpdateToBackend(newSessionConfig);

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_selectedModuleType!.label}模型已更新'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('更新模型配置失败: $e')),
        );
      }
    }
  }

  /// 向后端发送配置更新请求
  Future<void> _sendConfigUpdateToBackend(SessionModelConfig sessionConfig) async {
    try {
      // 获取conversation来获取sessionId
      final conversationProvider = context.read<ConversationProvider>();
      final conversation = conversationProvider.getConversationById(widget.conversationId);
      if (conversation == null) {
        logE('对话不存在，无法发送配置更新请求');
        return;
      }

      // 获取DiyServiceProvider
      final diyServiceProvider = context.read<DiyServiceProvider>();
      final diyService = await diyServiceProvider.getServiceForConversation(conversation);

      // 获取sessionId
      final sessionId = conversation.diySessionId;
      if (sessionId == null || sessionId.isEmpty) {
        logE('Session ID为空，无法发送配置更新请求');
        return;
      }

      // 构建模型配置数据
      // 注意：前端只需传递模型名称，后端会根据模型名称自动解析provider
      final Map<String, dynamic> modelConfig = {};

      // 遍历所有模块类型，构建配置
      for (final moduleType in mi.ModuleType.values) {
        final modelName = sessionConfig.getModel(moduleType.code);
        if (modelName != null) {
          // 只传递模型名称字符串，不传递嵌套的provider和model对象
          modelConfig[moduleType.code] = modelName;
        }
      }

      // 生成请求ID
      final requestId = 'config_${DateTime.now().millisecondsSinceEpoch}';

      logI('发送配置更新请求: sessionId=$sessionId, modelConfig=$modelConfig, requestId=$requestId');

      // 检查WebSocket管理器
      final wsManager = diyService.textWebSocketManager;
      logI('WebSocket管理器状态: wsManager=${wsManager != null ? "已初始化" : "为null"}');
      if (wsManager != null) {
        logI('WebSocket连接状态: isConnected=${wsManager.isConnected}');
      }

      // 调用WebSocket管理器发送配置更新请求
      diyService.textWebSocketManager?.sendConfigRequest(
        sessionId: sessionId,
        modelConfig: modelConfig,
        requestId: requestId,
      );

      logI('配置更新请求已发送');
    } catch (e) {
      logE('发送配置更新请求失败: $e');
      // 不阻塞UI操作，仅在日志中记录错误
    }
  }
}

/// 模块类型卡片
class _ModuleTypeCard extends StatelessWidget {
  final mi.ModuleType moduleType;
  final String? serverModel;
  final String? sessionModel;
  final bool hasAvailableModels;
  final VoidCallback onTap;

  const _ModuleTypeCard({
    required this.moduleType,
    required this.serverModel,
    required this.sessionModel,
    required this.hasAvailableModels,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final displayModel = sessionModel ?? serverModel;
    final isCustom = sessionModel != null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: hasAvailableModels ? onTap : null,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: hasAvailableModels
                  ? (isDark ? const Color(0xFF3A3A3A) : Colors.grey.shade200)
                  : Colors.grey.shade300,
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
                  color: hasAvailableModels ? const Color(0xFF10B981) : Colors.grey.shade400,
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
                    Row(
                      children: [
                        Text(
                          moduleType.label,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: hasAvailableModels
                                ? theme.colorScheme.onSurface
                                : Colors.grey.shade500,
                          ),
                        ),
                        if (isCustom) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF1E3A8A).withValues(alpha: 0.3)
                                  : Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '自定义',
                              style: TextStyle(
                                fontSize: 10,
                                color: isDark ? const Color(0xFF93C5FD) : Colors.blue.shade600,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      displayModel ?? '未配置',
                      style: TextStyle(
                        fontSize: 14,
                        color: displayModel != null
                            ? (isDark ? const Color(0xFFB0B0B0) : Colors.grey.shade600)
                            : Colors.grey.shade400,
                      ),
                    ),
                  ],
                ),
              ),
              // 右箭头
              Icon(
                Icons.chevron_right,
                color: hasAvailableModels
                    ? (isDark ? const Color(0xFF757575) : Colors.grey.shade400)
                    : Colors.grey.shade300,
                size: 22,
              ),
            ],
          ),
        ),
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
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF10B981)
                  : (isDark ? const Color(0xFF3A3A3A) : Colors.grey.shade200),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              // 模型信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      model.displayName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isSelected
                            ? const Color(0xFF10B981)
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                    if (model.description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        model.description,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? const Color(0xFFB0B0B0) : Colors.grey.shade600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
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
