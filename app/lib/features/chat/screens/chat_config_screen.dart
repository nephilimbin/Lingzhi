import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:ai_assistant/core/providers/config_provider.dart';
import 'package:ai_assistant/core/providers/conversation_provider.dart';
import 'package:ai_assistant/core/models/conversation.dart';
import 'package:ai_assistant/core/models/diy_config.dart';
import 'package:ai_assistant/core/models/dify_config.dart';
import 'package:ai_assistant/core/models/session_model_config.dart';
import 'package:ai_assistant/core/models/server_model_config.dart';
import 'package:ai_assistant/core/utils/app_logger.dart';
import 'package:ai_assistant/features/chat/screens/font_size_setting_screen.dart';
import 'package:ai_assistant/features/chat/screens/prompt_edit_screen.dart';
import 'package:ai_assistant/features/chat/screens/session_model_settings_screen.dart';
import 'package:ai_assistant/features/settings/screens/server_settings_screen.dart';
import 'package:ai_assistant/features/conversation/models/service_type_config.dart';

/// ChatConfigScreen - 对话配置设置页面
///
/// 设计规范（参考 add_service_screen.dart）:
/// - 背景: #F9FAFB
/// - 卡片: 白色背景, 圆角 16px, 阴影 alpha:0.05, blur:10, offset:(0,2)
/// - 字段: padding 16x14, 底部分隔线 #F3F4F6
/// - 标签: 15px, w600, #111827
/// - 内容: 14px, #111827, 右对齐
class ChatConfigScreen extends StatefulWidget {
  final String conversationId;
  final String initialTitle;
  final ConversationType conversationType;
  final String? configId;

  const ChatConfigScreen({
    required this.conversationId,
    required this.initialTitle,
    required this.conversationType,
    required this.configId,
    super.key,
  });

  @override
  State<ChatConfigScreen> createState() => _ChatConfigScreenState();
}

class _ChatConfigScreenState extends State<ChatConfigScreen> {
  late TextEditingController _nameController;
  String _apiPath = '';
  String _configServiceName = '';
  bool _isConfigMissing = false;
  SessionModelConfig? _sessionModelConfig;
  ServerModelConfig? _serverModelConfig;
  bool _isSessionIdVisible = false;
  String? _diySessionId; // 服务器返回的 Session ID

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialTitle);
    _loadConfigDetails();
  }

  void _loadConfigDetails() {
    final configProvider = Provider.of<ConfigProvider>(context, listen: false);
    final conversationProvider = Provider.of<ConversationProvider>(context, listen: false);

    // 从 ConversationProvider 获取最新的 conversation，而不是使用 widget.configId
    final latestConversation = conversationProvider.getConversationById(widget.conversationId);
    final currentConfigId = latestConversation?.configId ?? '';

    // 获取服务器返回的 Session ID
    _diySessionId = latestConversation?.diySessionId;

    if (currentConfigId.isEmpty) {
      _isConfigMissing = true;
      _apiPath = 'N/A';
      _configServiceName = 'N/A';
      if (mounted) {
        setState(() {});
      }
      return;
    }

    try {
      if (widget.conversationType == ConversationType.diy) {
        final diyConfig = configProvider.diyConfigs.firstWhere(
          (config) => config.id == currentConfigId,
          orElse: () => throw Exception('配置不存在'),
        );
        _isConfigMissing = false;
        _apiPath = diyConfig.websocketUrl;
        _configServiceName = diyConfig.name;

        // 加载模型配置
        _sessionModelConfig = latestConversation?.sessionModelConfig;
        _serverModelConfig = configProvider.getModelConfig(currentConfigId);
      } else if (widget.conversationType == ConversationType.dify) {
        final difyConfig = configProvider.difyConfigs.firstWhere(
          (config) => config.id == currentConfigId,
          orElse: () => throw Exception('配置不存在'),
        );
        _isConfigMissing = false;
        _apiPath = difyConfig.apiUrl;
        _configServiceName = difyConfig.name;

        // Dify服务暂不支持模型配置
        _sessionModelConfig = null;
        _serverModelConfig = null;
      }
    } catch (e) {
      logE("Error loading config details for configId $currentConfigId: $e");
      _isConfigMissing = true; // 配置不存在
      _apiPath = 'N/A';
      _configServiceName = '配置已删除';
      _sessionModelConfig = null;
      _serverModelConfig = null;
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _saveConversationTitle() {
    final conversationProvider = Provider.of<ConversationProvider>(
      context,
      listen: false,
    );
    final newTitle = _nameController.text.trim();

    if (newTitle.isNotEmpty && newTitle != widget.initialTitle) {
      conversationProvider.updateConversationTitle(
        widget.conversationId,
        newTitle,
      );
      logI('Title updated to: $newTitle for id: ${widget.conversationId}');
    } else if (newTitle.isEmpty) {
      _nameController.text = widget.initialTitle;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('对话标题不能为空')),
        );
      }
    }
  }

  void _copyToClipboard(String text, String fieldName) {
    if (text.isNotEmpty &&
        text != 'N/A' &&
        text != '配置ID无效或未提供' &&
        text != '无法加载API路径' &&
        text != '无法加载服务名称') {
      Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$fieldName 已复制到剪贴板'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('没有可复制的内容'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // 根据主题获取颜色
    final backgroundColor = theme.colorScheme.surface;
    final cardBackground = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final dividerColor = isDark ? const Color(0xFF3A3A3A) : const Color(0xFFF3F4F6);
    final labelColor = theme.colorScheme.onSurface;
    final contentColor = theme.colorScheme.onSurface;
    final hintColor = isDark ? const Color(0xFFB0B0B0) : const Color(0xFF9CA3AF);

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) {
          _saveConversationTitle();
        }
      },
      child: Scaffold(
        backgroundColor: backgroundColor,
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(labelColor),
              Container(
                height: 1,
                color: dividerColor,
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  child: Column(
                    children: [
                      // 基础信息卡片
                      _buildBasicInfoCard(cardBackground, dividerColor, labelColor, contentColor, hintColor),
                      const SizedBox(height: 12),
                      // 连接信息卡片
                      _buildConnectionInfoCard(cardBackground, dividerColor, labelColor, contentColor, hintColor),
                      const SizedBox(height: 12),
                      // 会话模型配置卡片 - 仅在自定义服务下显示
                      if (widget.conversationType == ConversationType.diy)
                        _buildSessionModelConfigCard(cardBackground, labelColor),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建自定义Header
  Widget _buildHeader(Color labelColor) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      color: theme.colorScheme.surface,
      child: Row(
        children: [
          // 返回按钮
          InkWell(
            onTap: () {
              _saveConversationTitle();
              Navigator.of(context).pop();
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.all(8),
              child: Icon(
                Icons.arrow_back,
                color: labelColor,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // 标题
          Text(
            '对话设置',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: labelColor,
            ),
          ),
        ],
      ),
    );
  }

  /// 基础信息卡片
  Widget _buildBasicInfoCard(Color cardBackground, Color dividerColor, Color labelColor, Color contentColor, Color hintColor) {
    return Container(
      decoration: BoxDecoration(
        color: cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: dividerColor,
          width: 1,
        ),
      ),
      child: Column(
        children: [
          _buildConversationNameField(labelColor, contentColor, hintColor),
          _buildDivider(dividerColor),
          _buildSessionIdField(labelColor, contentColor, hintColor),
          _buildDivider(dividerColor),
          _buildFontSizeField(labelColor, hintColor),
        ],
      ),
    );
  }

  /// 连接信息卡片
  Widget _buildConnectionInfoCard(Color cardBackground, Color dividerColor, Color labelColor, Color contentColor, Color hintColor) {
    return Container(
      decoration: BoxDecoration(
        color: cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: dividerColor,
          width: 1,
        ),
      ),
      child: Column(
        children: [
          _buildServerTypeField(labelColor, contentColor),
          _buildDivider(dividerColor),
          _buildConfigServerField(labelColor, contentColor, hintColor),
          _buildDivider(dividerColor),
          _buildApiPathField(labelColor, hintColor),
        ],
      ),
    );
  }

  /// 会话模型配置卡片 - 简化为单个条目
  Widget _buildSessionModelConfigCard(Color cardBackground, Color labelColor) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dividerColor = isDark ? const Color(0xFF3A3A3A) : Colors.grey.shade200;

    // 计算自定义模型数量
    int customModelCount = 0;
    if (_sessionModelConfig != null && _serverModelConfig != null) {
      for (final entry in _sessionModelConfig!.selectedModels.entries) {
        final sessionValue = entry.value;
        final serverValue = _serverModelConfig!.getModel(entry.key);
        // 只有当会话配置的值与服务器配置不同时，才算自定义
        if (sessionValue != null && sessionValue != serverValue) {
          customModelCount++;
        }
      }
    }

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SessionModelSettingsScreen(
              conversationId: widget.conversationId,
              sessionConfig: _sessionModelConfig,
              configId: widget.configId ?? '',
            ),
          ),
        ).then((_) {
          // 返回后重新加载配置
          _loadConfigDetails();
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: cardBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: dividerColor,
            width: 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              // 左侧图标
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.model_training_outlined,
                  color: Color(0xFF10B981),
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              // 中间内容
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '当前会话模型',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: labelColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      customModelCount > 0
                          ? '已自定义 $customModelCount 个模型'
                          : '跟随服务器配置',
                      style: TextStyle(
                        fontSize: 13,
                        color: customModelCount > 0
                            ? Colors.blue.shade600
                            : Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
              // 右箭头
              Icon(
                Icons.chevron_right,
                color: isDark ? const Color(0xFF757575) : Colors.grey.shade400,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 分隔线
  Widget _buildDivider(Color dividerColor) {
    return Container(
      margin: const EdgeInsets.only(left: 106), // 90(label width) + 16(spacing)
      height: 1,
      color: dividerColor,
    );
  }

  /// 获取当前对话的服务器类型配置
  ServiceTypeConfig _getServerTypeConfig() {
    switch (widget.conversationType) {
      case ConversationType.diy:
        return ServiceTypeConfigs.customService;
      case ConversationType.dify:
        return ServiceTypeConfigs.difyService;
    }
  }

  /// 对话名称字段 - 带清空按钮
  Widget _buildConversationNameField(Color labelColor, Color contentColor, Color hintColor) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return _buildFormField(
      label: '对话名称',
      labelColor: labelColor,
      content: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _nameController,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 14,
                color: contentColor,
                height: 1.0,
              ),
              decoration: InputDecoration(
                hintText: '输入对话名称',
                hintStyle: TextStyle(
                  color: hintColor,
                  fontSize: 14,
                  height: 1.0,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 4),
                isDense: true,
              ),
              maxLines: 1,
              onChanged: (value) {
                setState(() {}); // 更新清空按钮状态
              },
            ),
          ),
          // 清空按钮 - 当有内容时显示
          if (_nameController.text.isNotEmpty)
            InkWell(
              onTap: () {
                setState(() {
                  _nameController.clear();
                });
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.cancel,
                  size: 18,
                  color: isDark ? const Color(0xFF757575) : Colors.grey.shade400,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Session ID 字段 - 只读，支持显示/隐藏和复制
  Widget _buildSessionIdField(Color labelColor, Color contentColor, Color hintColor) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 使用服务器返回的 Session ID，如果为空则显示占位符
    final sessionId = _diySessionId ?? '未连接';
    final hasValidSessionId = _diySessionId != null && _diySessionId!.isNotEmpty;
    final displayText = _isSessionIdVisible
        ? sessionId
        : (hasValidSessionId ? '•' * (sessionId.length > 12 ? 12 : sessionId.length) : sessionId);

    return _buildFormField(
      label: 'Session ID',
      labelColor: labelColor,
      content: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Session ID 显示文本
          Expanded(
            child: Text(
              displayText,
              style: TextStyle(
                fontSize: 14,
                color: hintColor,
                letterSpacing: _isSessionIdVisible ? 0 : 2,
              ),
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          // 显示/隐藏按钮
          InkWell(
            onTap: () {
              setState(() {
                _isSessionIdVisible = !_isSessionIdVisible;
              });
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(4),
              child: Icon(
                _isSessionIdVisible ? Icons.visibility_off : Icons.visibility,
                size: 18,
                color: isDark ? const Color(0xFF757575) : Colors.grey.shade500,
              ),
            ),
          ),
          const SizedBox(width: 4),
          // 复制按钮 - 仅在有有效 Session ID 时可用
          InkWell(
            onTap: () {
              if (hasValidSessionId) {
                _copyToClipboard(_diySessionId!, 'Session ID');
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('暂无可复制的 Session ID'),
                    duration: Duration(seconds: 1),
                  ),
                );
              }
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.copy,
                size: 18,
                color: isDark ? const Color(0xFF757575) : Colors.grey.shade500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 提示词字段 - 点击进入编辑页面
  Widget _buildPromptField(Color labelColor, Color hintColor) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const PromptEditScreen()),
        );
      },
      borderRadius: BorderRadius.circular(4),
      child: _buildFormField(
        label: '提示词',
        labelColor: labelColor,
        content: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              '点击编辑',
              style: TextStyle(fontSize: 14, color: hintColor),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, color: hintColor.withValues(alpha: 0.8), size: 20),
          ],
        ),
      ),
    );
  }

  /// 文字大小字段 - 点击进入文字大小设置页面
  Widget _buildFontSizeField(Color labelColor, Color hintColor) {
    return InkWell(
      onTap: () async {
        await Navigator.push<double>(
          context,
          MaterialPageRoute(
            builder:
                (context) => FontSizeSettingScreen(
                  conversationId: widget.conversationId,
                ),
          ),
        );
        // 返回到 ChatConfigScreen，用户可以继续操作或手动返回
        // 字体大小已经在 FontSizeSettingScreen 中保存到 SharedPreferences
      },
      borderRadius: BorderRadius.circular(12),
      child: _buildFormField(
        label: '文字大小',
        labelColor: labelColor,
        content: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              '点击设置',
              style: TextStyle(fontSize: 14, color: hintColor),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, color: hintColor.withValues(alpha: 0.8), size: 20),
          ],
        ),
      ),
    );
  }

  /// 服务器类型字段 - 只读显示
  Widget _buildServerTypeField(Color labelColor, Color contentColor) {
    final serverTypeConfig = _getServerTypeConfig();

    return _buildFormField(
      label: '服务器类型',
      labelColor: labelColor,
      content: Text(
        serverTypeConfig.displayName,
        style: TextStyle(
          fontSize: 14,
          color: contentColor,
        ),
        textAlign: TextAlign.right,
      ),
    );
  }

  /// 配置服务器字段 - 始终可点击，允许重新选择
  Widget _buildConfigServerField(Color labelColor, Color contentColor, Color hintColor) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: () {
        // 显示重新选择对话框
        _showConfigSelectionDialog();
      },
      onLongPress: () => _copyToClipboard(_configServiceName, '服务器'),
      child: _buildFormField(
        label: '配置服务器',
        labelColor: labelColor,
        content: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Expanded(
              child: Text(
                _configServiceName.isNotEmpty ? _configServiceName : 'N/A',
                style: TextStyle(
                  fontSize: 14,
                  color: _isConfigMissing ? Colors.blue : contentColor,
                ),
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right,
              color: _isConfigMissing ? Colors.blue : (isDark ? const Color(0xFF757575) : Colors.grey.shade400),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  /// 配置 API 路径字段 - 可长按复制
  Widget _buildApiPathField(Color labelColor, Color hintColor) {
    return InkWell(
      onLongPress: () => _copyToClipboard(_apiPath, 'API路径'),
      child: _buildFormField(
        label: '配置API路径',
        labelColor: labelColor,
        content: Text(
          _apiPath.isNotEmpty ? _apiPath : 'N/A',
          style: TextStyle(fontSize: 14, color: hintColor),
          textAlign: TextAlign.right,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  /// 通用表单字段 - 参考 add_service_screen 样式
  /// 左侧：标签（固定宽度90px）
  /// 右侧：内容（右对齐）
  Widget _buildFormField({required String label, required Color labelColor, required Widget content}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 左侧标签 - 固定宽度90px
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: labelColor,
              ),
            ),
          ),
          const SizedBox(width: 16),
          // 右侧内容 - 右对齐
          Expanded(
            child: SizedBox(
              height: 30,
              child: Align(alignment: Alignment.centerRight, child: content),
            ),
          ),
        ],
      ),
    );
  }

  /// 显示配置选择对话框（iOS风格）
  void _showConfigSelectionDialog() {
    final configProvider = Provider.of<ConfigProvider>(context, listen: false);
    final availableConfigs =
        widget.conversationType == ConversationType.diy
            ? configProvider.diyConfigs
            : configProvider.difyConfigs;

    // 没有可用的配置，直接跳转到服务器设置页面
    if (availableConfigs.isEmpty) {
      _showNoConfigDialogAndNavigate();
      return;
    }

    // iOS风格的底部选择器
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext bottomSheetContext) {
        final theme = Theme.of(bottomSheetContext);
        final isDark = theme.brightness == Brightness.dark;
        final labelColor = theme.colorScheme.onSurface;

        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 顶部标题栏
              Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: isDark ? const Color(0xFF3A3A3A) : Colors.grey.shade200,
                      width: 0.5,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 16),
                    Text(
                      '选择服务器',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: labelColor,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.of(bottomSheetContext).pop(),
                      child: const Text(
                        '取消',
                        style: TextStyle(
                          fontSize: 17,
                          color: Colors.blue,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // 配置列表
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(bottomSheetContext).size.height * 0.5,
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: availableConfigs.length,
                  itemBuilder: (context, index) {
                    final config = availableConfigs[index];
                    final isSelected = config.id == widget.configId;

                    return InkWell(
                      onTap: () async {
                        Navigator.of(bottomSheetContext).pop();
                        await _updateConversationConfig(config.id);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: isDark ? const Color(0xFF3A3A3A) : Colors.grey.shade200,
                              width: 0.5,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            // 图标
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: config.icon.backgroundColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                widget.conversationType == ConversationType.diy
                                    ? Icons.smart_toy
                                    : Icons.chat_bubble_outline,
                                color: config.icon.backgroundColor,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            // 配置名称和URL
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    config.name,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      color: labelColor,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    widget.conversationType ==
                                            ConversationType.diy
                                        ? (config as DiyConfig).websocketUrl
                                        : (config as DifyConfig).apiUrl,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: isDark ? const Color(0xFFB0B0B0) : Colors.grey.shade600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            // 选中标记
                            if (isSelected)
                              const Icon(
                                Icons.check,
                                color: Colors.blue,
                                size: 24,
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              // 底部安全区域
              SizedBox(height: MediaQuery.of(bottomSheetContext).padding.bottom),
            ],
          ),
        );
      },
    );
  }

  /// 显示没有配置的对话框并导航到服务器设置
  void _showNoConfigDialogAndNavigate() {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return CupertinoAlertDialog(
          title: '暂无可用配置',
          content: '您还没有添加服务器配置。\n\n是否前往添加？',
          actions: [
            CupertinoDialogAction(
              child: '取消',
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              child: '前往添加',
              onPressed: () {
                Navigator.of(dialogContext).pop();
                // 跳转到服务器设置页面
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ServerSettingsScreen(),
                  ),
                ).then((_) {
                  // 从服务器设置页面返回后，重新加载配置
                  if (mounted) {
                    _loadConfigDetails();
                  }
                });
              },
            ),
          ],
        );
      },
    );
  }

  /// 更新对话的配置
  Future<void> _updateConversationConfig(String newConfigId) async {
    final conversationProvider = Provider.of<ConversationProvider>(
      context,
      listen: false,
    );

    try {
      await conversationProvider.updateConversationConfig(
        widget.conversationId,
        newConfigId,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('配置已更新，请重新进入对话'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }

      // 配置更新成功后，返回到home页面（弹出chat_config和chat两个页面）
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst || route.settings.name == '/home');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('配置更新失败: $e')),
        );
      }
    }
  }
}

/// iOS风格的AlertDialog组件
class CupertinoAlertDialog extends StatelessWidget {
  final String? title;
  final String? content;
  final List<CupertinoDialogAction> actions;

  const CupertinoAlertDialog({
    required this.actions,
    this.title,
    this.content,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final labelColor = theme.colorScheme.onSurface;

    return AlertDialog(
      backgroundColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      title: title != null
          ? Text(
              title!,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: labelColor,
              ),
            )
          : null,
      content: content != null
          ? Text(
              content!,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? const Color(0xFFE0E0E0) : Colors.black87,
                height: 1.5,
              ),
            )
          : null,
      actions: actions.map((action) {
        return TextButton(
          onPressed: action.onPressed,
          style: TextButton.styleFrom(
            foregroundColor:
                action.isDefaultAction ? Colors.blue : (isDark ? const Color(0xFFB0B0B0) : Colors.grey.shade600),
          ),
          child: Text(
            action.child ?? '',
            style: TextStyle(
              fontSize: 17,
              fontWeight: action.isDefaultAction ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// CupertinoDialogAction组件
class CupertinoDialogAction {
  final String? child;
  final VoidCallback? onPressed;
  final bool isDefaultAction;
  final bool isDestructiveAction;

  CupertinoDialogAction({
    this.child,
    this.onPressed,
    this.isDefaultAction = false,
    this.isDestructiveAction = false,
  });
}
