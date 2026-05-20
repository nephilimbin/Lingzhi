import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ai_assistant/core/models/server_model_config.dart';
import 'package:ai_assistant/core/providers/config_provider.dart';
import 'package:ai_assistant/core/providers/conversation_provider.dart';
import 'package:ai_assistant/features/conversation/providers/conversation_type_provider.dart';
import 'package:ai_assistant/features/conversation/widgets/service_selector_button.dart';
import 'package:ai_assistant/features/conversation/widgets/config_detail_card.dart';
import 'package:ai_assistant/features/conversation/widgets/model_config_card.dart';
import 'package:ai_assistant/features/conversation/models/service_type_config.dart';

/// 新建对话类型选择屏幕
///
/// 功能说明：
/// 1. 选择服务类型（自定义服务 / Dify服务）
/// 2. 选择具体的服务配置
/// 3. 显示选中配置的详细信息
/// 4. 创建新对话并导航到聊天页面
class ConversationTypeScreen extends StatefulWidget {
  const ConversationTypeScreen({super.key});

  @override
  State<ConversationTypeScreen> createState() => _ConversationTypeScreenState();
}

class _ConversationTypeScreenState extends State<ConversationTypeScreen> {
  late ConversationTypeProvider _conversationTypeProvider;

  @override
  void initState() {
    super.initState();
    final conversationProvider = Provider.of<ConversationProvider>(
      context,
      listen: false,
    );
    final configProvider = Provider.of<ConfigProvider>(context, listen: false);
    _conversationTypeProvider = ConversationTypeProvider(
      context: context,
      conversationProvider: conversationProvider,
      configProvider: configProvider,
    );
  }

  @override
  void dispose() {
    _conversationTypeProvider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ChangeNotifierProvider.value(
      value: _conversationTypeProvider,
      child: Consumer<ConversationTypeProvider>(
        builder: (context, provider, child) {
          final isDark = theme.brightness == Brightness.dark;
          return Scaffold(
            backgroundColor: theme.colorScheme.surface,
            body: SafeArea(
              child: Column(
                children: [
                  _buildHeader(provider),
                  Container(
                    height: 1,
                    color: isDark ? const Color(0xFF3A3A3A) : const Color(0xFFE5E7EB),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 服务类型选择器
                            ServiceSelectorButton(
                              title: '服务类型',
                              selectedValue:
                                  provider.selectedServiceType?.displayName,
                              enabled: true,
                              icon: Icons.cloud_outlined,
                              onTap: provider.showServiceTypeSelector,
                              placeholder: '请选择服务类型',
                            ),
                            const SizedBox(height: 12),

                            // 服务配置选择器
                            ServiceSelectorButton(
                              title: '服务配置',
                              selectedValue: _getSelectedConfigName(provider),
                              enabled: provider.selectedServiceType != null,
                              icon: Icons.settings_outlined,
                              onTap:
                                  provider.selectedServiceType != null
                                      ? () {
                                        provider.showConfigSelector();
                                      }
                                      : null,
                              placeholder: '请先选择服务类型',
                            ),

                            // 配置详情卡片
                            const SizedBox(height: 12),
                            ..._buildConfigDetailCard(provider),
                            // 模型配置卡片
                            const SizedBox(height: 12),
                            ..._buildModelConfigCard(provider),
                            const SizedBox(height: 80),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // 创建对话按钮
                  _buildBottomBar(provider),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 构建自定义Header
  Widget _buildHeader(ConversationTypeProvider provider) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      color: theme.colorScheme.surface,
      child: Row(
        children: [
          // 返回按钮
          InkWell(
            onTap: provider.navigateBack,
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
            '新建对话',
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

  /// 获取选中配置的名称
  String? _getSelectedConfigName(ConversationTypeProvider provider) {
    if (provider.selectedServiceType?.id ==
        ServiceTypeConfigs.customService.id) {
      return provider.selectedDiyConfig?.name;
    } else if (provider.selectedServiceType?.id ==
        ServiceTypeConfigs.difyService.id) {
      return provider.selectedDifyConfig?.name;
    }
    return null;
  }

  /// 构建配置详情卡片
  List<Widget> _buildConfigDetailCard(ConversationTypeProvider provider) {
    if (provider.selectedServiceType == null) {
      return [];
    }

    if (provider.selectedServiceType!.id ==
        ServiceTypeConfigs.customService.id) {
      final config = provider.selectedDiyConfig;
      if (config == null) {
        return [];
      }

      return [
        ConfigDetailCard(
          name: config.name,
          details: [
            ConfigDetailItem(label: '服务地址', value: config.websocketUrl),
            ConfigDetailItem(label: '设备标识', value: config.macAddress),
            ConfigDetailItem(label: 'Token', value: config.token),
          ],
        ),
      ];
    }

    if (provider.selectedServiceType!.id == ServiceTypeConfigs.difyService.id) {
      final config = provider.selectedDifyConfig;
      if (config == null) {
        return [];
      }

      return [
        ConfigDetailCard(
          name: config.name,
          details: [
            ConfigDetailItem(label: 'API地址', value: config.apiUrl),
            ConfigDetailItem(label: 'API密钥', value: _maskApiKey(config.apiKey)),
          ],
        ),
      ];
    }

    return [];
  }

  /// 掩码API密钥（只显示前4位和后4位）
  String _maskApiKey(String apiKey) {
    if (apiKey.length <= 8) {
      return apiKey;
    }
    return '${apiKey.substring(0, 4)}...${apiKey.substring(apiKey.length - 4)}';
  }

  /// 构建创建对话按钮
  Widget _buildBottomBar(ConversationTypeProvider provider) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF3A3A3A) : Colors.grey.shade200,
            width: 1,
          ),
        ),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton(
          onPressed:
              provider.canCreateConversation
                  ? provider.createConversation
                  : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.grey.shade400,
            elevation: 0,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(
            '创建对话',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
        ),
      ),
    );
  }

  /// 构建模型配置卡片
  List<Widget> _buildModelConfigCard(ConversationTypeProvider provider) {
    // 只在自定义服务配置下显示模型配置
    if (provider.selectedServiceType?.id !=
        ServiceTypeConfigs.customService.id) {
      return [];
    }

    final config = provider.selectedDiyConfig;
    if (config == null) {
      return [];
    }

    // 获取该服务器的模型配置，如果没有配置则传入空配置
    final modelConfig =
        provider.configProvider.getModelConfig(config.id) ??
        ServerModelConfig.empty(config.id);

    return [ModelConfigCard(config: modelConfig)];
  }
}
