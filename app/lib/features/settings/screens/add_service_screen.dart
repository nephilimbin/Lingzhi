import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ai_assistant/core/providers/config_provider.dart';
import 'package:ai_assistant/core/models/icon_option.dart';
import 'package:ai_assistant/features/settings/providers/settings_provider.dart';
import 'package:ai_assistant/core/api/connection_tester.dart';
import 'package:ai_assistant/core/services/mac_address_service.dart';
import 'package:ai_assistant/core/utils/app_logger.dart';

/// 添加服务页面
///
/// 根据Figma设计实现：
/// - 自定义Header带返回按钮和标题
/// 🔒 隐藏 Dify 服务：服务类型选择（自定义服务/Dify服务）
/// - 服务类型选择（自定义服务）
/// - 基础信息卡片（服务名称、服务类型）- 一行两列布局
/// - 服务器配置卡片（根据服务类型动态变化）- 一行两列布局
/// - 说明卡片（蓝色背景）
/// - 底部添加服务按钮（黑色背景，圆角12px）
class AddServiceScreen extends StatefulWidget {
  const AddServiceScreen({super.key});

  @override
  State<AddServiceScreen> createState() => _AddServiceScreenState();
}

class _AddServiceScreenState extends State<AddServiceScreen> {
  /// 服务类型枚举
  ServiceType _selectedServiceType = ServiceType.diy;

  /// 选中的图标选项
  IconOption _selectedIcon = availableIcons.first;

  /// 表单控制器
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _macAddressController = TextEditingController();
  final TextEditingController _tokenController = TextEditingController();
  // 🔒 隐藏 Dify 服务：final TextEditingController _apiKeyController = TextEditingController();

  /// 表单key
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  /// 自动生成的MAC地址
  String? _generatedMacAddress;

  /// 是否正在保存
  bool _isSaving = false;

  /// 是否正在测试连接
  bool _isTesting = false;

  /// Token是否可见
  bool _isTokenVisible = false;

  /// 服务器配置信息（用于协议检查）
  ServerConfigInfo? _serverConfigInfo;

  @override
  void initState() {
    super.initState();
    _loadGeneratedMacAddress();
  }

  /// 加载自动生成的MAC地址
  Future<void> _loadGeneratedMacAddress() async {
    try {
      final macAddress = await MacAddressService().getMacAddress();
      if (mounted) {
        setState(() {
          _generatedMacAddress = macAddress;
        });
      }
    } catch (e) {
      logE('加载MAC地址失败: $e');
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _macAddressController.dispose();
    _tokenController.dispose();
    // 🔒 隐藏 Dify 服务：_apiKeyController.dispose();
    super.dispose();
  }

  /// 切换服务类型
  // 🔒 隐藏 Dify 服务：当前仅支持自定义服务，暂不支持切换
  /*
  void _switchServiceType(ServiceType type) {
    setState(() {
      _selectedServiceType = type;
      // 切换时清空相关表单
      _urlController.clear();
      _macAddressController.clear();
      _tokenController.clear();
      _apiKeyController.clear();
    });
  }
  */

  /// 验证并保存服务配置
  Future<void> _saveService() async {
    // 手动验证表单
    final url = _urlController.text.trim();
    if (_nameController.text.trim().isEmpty) {
      _showErrorSnackBar('请输入服务名称');
      return;
    }
    if (url.isEmpty) {
      _showErrorSnackBar('请输入服务器地址');
      return;
    }
    // 验证URL格式
    final uri = Uri.tryParse(url);
    if (uri == null ||
        (!uri.hasScheme &&
            !url.startsWith('ws://') &&
            !url.startsWith('wss://'))) {
      _showErrorSnackBar('请输入有效的服务器地址（ws://或wss://开头）');
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final configProvider = context.read<ConfigProvider>();
      final settingsProvider = context.read<SettingsProvider>();

      // 设置控制器值并调用添加方法
      // 🔒 隐藏 Dify 服务：当前仅支持自定义服务
      // if (_selectedServiceType == ServiceType.diy) {
      settingsProvider.newDiyNameController.text = _nameController.text.trim();
      settingsProvider.newDiyWebsocketUrlController.text =
          _urlController.text.trim();
      // 不再使用用户输入的MAC地址，使用自动生成的
      settingsProvider.newDiyMacAddressController.text = _generatedMacAddress ?? '';
      settingsProvider.newDiyTokenController.text =
          _tokenController.text.trim();

      /// 设置选中的图标
      settingsProvider.selectedDiyIcon = _selectedIcon;

      await settingsProvider.addDiyConfig(configProvider);
      /* 🔒 隐藏 Dify 服务：else {
        settingsProvider.newDifyNameController.text =
            _nameController.text.trim();
        settingsProvider.newDifyApiUrlController.text =
            _urlController.text.trim();
        settingsProvider.newDifyApiKeyController.text =
            _apiKeyController.text.trim();

        /// 设置选中的图标
        settingsProvider.selectedDifyIcon = _selectedIcon;

        await settingsProvider.addDifyConfig(configProvider);
      }
      */

      if (mounted) {
        // 显示成功提示
        // 🔒 隐藏 Dify 服务：当前仅支持自定义服务
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('自定义服务添加成功'),
            // 🔒 隐藏 Dify 服务：Text(
            //   '${_selectedServiceType == ServiceType.diy ? '自定义服务' : 'Dify服务'}添加成功',
            // ),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 1),
          ),
        );
        // 返回上一页
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        // 显示错误提示
        _showErrorSnackBar('添加失败: ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  /// 显示错误提示
  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      ),
    );
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
            // 自定义Header
            _buildHeader(),
            // 分割线
            Container(
              height: 1,
              color: isDark ? const Color(0xFF3A3A3A) : const Color(0xFFE5E7EB),
            ),
            // 内容区域
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      // 基础信息卡片
                      _buildBasicInfoCard(),
                      const SizedBox(height: 12),
                      // 服务器配置卡片
                      _buildServerConfigCard(),
                      const SizedBox(height: 12),
                      // 说明卡片
                      _buildInfoCard(),
                      const SizedBox(height: 24),
                      // 底部留白，为固定按钮栏留出空间
                      const SizedBox(height: 80),
                    ],
                  ),
                ),
              ),
            ),
            // 固定底部按钮栏
            _buildBottomBar(),
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
      color: theme.colorScheme.surface,
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
            '添加服务',
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

  /// 构建基础信息卡片
  /// 采用一行两列布局，左侧标签，右侧输入框
  Widget _buildBasicInfoCard() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? const Color(0xFF3A3A3A) : Colors.grey.shade200,
            width: 1,
          ),
        ),
        child: Column(
          children: [
            // 服务名称 - 一行两列布局
            _buildTextFormField(
              label: '服务名称',
              isRequired: true,
              hintText: '例如：家庭助理',
              controller: _nameController,
            ),
            // 服务类型 - 一行两列布局，显示为只读字段
            // 🔒 隐藏 Dify 服务：当前仅支持自定义服务
            _buildServiceTypeField(),
            // 图标选择 - 新增字段
            _buildIconSelectorField(),
          ],
        ),
      ),
    );
  }

  /// 构建表单字段 - 通用字段构建方法
  /// 左侧：标签（固定宽度90px）
  /// 右侧：自定义内容（通过content参数传入）
  Widget _buildFormField({
    required String label,
    required bool isRequired,
    required Widget content,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF3A3A3A) : const Color(0xFFF3F4F6),
            width: 1,
          ),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 左侧标签 - 固定宽度确保右侧对齐一致
            SizedBox(
              width: 90,
              child: Row(
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  if (isRequired) ...[
                    const SizedBox(width: 2),
                    Text(
                      '*',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFFEF4444),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 16),
            // 右侧内容 - 使用Align确保垂直居中对齐
            Expanded(
              child: SizedBox(
                height: 30,
                child: Align(alignment: Alignment.centerRight, child: content),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建文本输入表单字段 - 辅助方法
  /// 用于快速创建带有TextFormField的字段
  Widget _buildTextFormField({
    required String label,
    required bool isRequired,
    required String hintText,
    required TextEditingController controller,
    bool obscureText = false,
    TextInputType keyboardType = TextInputType.text,
    Widget? suffixIcon,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return _buildFormField(
      label: label,
      isRequired: isRequired,
      content: TextFormField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        textAlign: TextAlign.right,
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(
            color: isDark ? const Color(0xFFB0B0B0) : const Color(0xFF9CA3AF),
            fontSize: 14,
            height: 1.0,
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 4),
          isDense: true,
          suffixIcon: suffixIcon,
          suffixIconConstraints: const BoxConstraints(
            minWidth: 24,
            minHeight: 24,
            maxWidth: 24,
            maxHeight: 24,
          ),
        ),
        style: TextStyle(
          fontSize: 14,
          color: theme.colorScheme.onSurface,
          height: 1.0,
        ),
      ),
    );
  }

  /// 构建MAC地址显示字段（只读）
  Widget _buildMacAddressDisplayField() {
    final theme = Theme.of(context);

    return _buildFormField(
      label: 'MAC地址',
      isRequired: false,
      content: Text(
        _generatedMacAddress ?? '加载中...',
        style: TextStyle(
          fontSize: 14,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
        ),
      ),
    );
  }

  /// 构建服务类型字段 - 使用统一字段构建方法
  /// 🔒 隐藏 Dify 服务：当前仅支持自定义服务，显示为不可点击的只读字段
  Widget _buildServiceTypeField() {
    final theme = Theme.of(context);

    return _buildFormField(
      label: '服务类型',
      isRequired: true,
      onTap: null, // 不允许点击
      content: Text(
        '自定义服务',
        style: TextStyle(
          fontSize: 14,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
        ),
      ),
    );
  }

  /// 构建图标选择字段
  Widget _buildIconSelectorField() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return _buildFormField(
      label: '图标',
      isRequired: false,
      onTap: () => _showIconPickerBottomSheet(),
      content: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: _selectedIcon.backgroundColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _selectedIcon.icon,
              color: _selectedIcon.iconColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _selectedIcon.name,
            style: TextStyle(
              fontSize: 14,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.keyboard_arrow_down,
            color: isDark ? const Color(0xFF757575) : Colors.grey.shade500,
            size: 20,
          ),
        ],
      ),
    );
  }

  /// 🔒 隐藏 Dify 服务：显示服务类型选择底部弹窗
  /*
  void _showServiceTypeBottomSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder:
          (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  child: const Text(
                    '选择服务类型',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(
                    Icons.cloud_outlined,
                    color: Color(0xFF16A34A),
                  ),
                  title: const Text('自定义服务'),
                  trailing:
                      _selectedServiceType == ServiceType.diy
                          ? const Icon(Icons.check, color: Color(0xFF16A34A))
                          : null,
                  onTap: () {
                    _switchServiceType(ServiceType.diy);
                    Navigator.of(context).pop();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.api, color: Color(0xFF2563EB)),
                  title: const Text('Dify服务'),
                  trailing:
                      _selectedServiceType == ServiceType.dify
                          ? const Icon(Icons.check, color: Color(0xFF2563EB))
                          : null,
                  onTap: () {
                    _switchServiceType(ServiceType.dify);
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
          ),
    );
  }
  */

  /// 显示图标选择底部弹窗
  void _showIconPickerBottomSheet() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: true,
      builder:
          (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    '选择图标',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                Divider(
                  height: 1,
                  color:
                      isDark ? const Color(0xFF3A3A3A) : Colors.grey.shade300,
                ),
                Container(
                  height: 400,
                  padding: const EdgeInsets.all(8),
                  child: GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          childAspectRatio: 1,
                        ),
                    itemCount: availableIcons.length,
                    itemBuilder: (context, index) {
                      final iconOption = availableIcons[index];
                      final bool isSelected =
                          _selectedIcon.icon == iconOption.icon;

                      return InkWell(
                        onTap: () {
                          setState(() {
                            _selectedIcon = iconOption;
                          });
                          Navigator.of(context).pop();
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          decoration: BoxDecoration(
                            color:
                                isSelected
                                    ? iconOption.backgroundColor.withValues(
                                      alpha: 0.2,
                                    )
                                    : (isDark
                                        ? const Color(0xFF2A2A2A)
                                        : Colors.grey.shade100),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color:
                                  isSelected
                                      ? iconOption.backgroundColor
                                      : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: iconOption.backgroundColor,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  iconOption.icon,
                                  color: iconOption.iconColor,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                iconOption.name,
                                style: TextStyle(
                                  fontSize: 11,
                                  color:
                                      isSelected
                                          ? iconOption.backgroundColor
                                          : (isDark
                                              ? const Color(0xFFB0B0B0)
                                              : Colors.grey.shade700),
                                  fontWeight:
                                      isSelected
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
    );
  }

  /// 构建服务器配置卡片
  /// 所有字段都在同一个Container中，使用border-b分隔
  /// 🔒 隐藏 Dify 服务：当前仅支持自定义服务
  Widget _buildServerConfigCard() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? const Color(0xFF3A3A3A) : Colors.grey.shade200,
            width: 1,
          ),
        ),
        child: Column(
          children: [
            // 🔒 隐藏 Dify 服务：当前仅支持自定义服务，移除服务类型判断
            // if (_selectedServiceType == ServiceType.diy) ...[
            // 自定义服务字段
            _buildTextFormField(
              label: '服务器地址',
              isRequired: true,
              hintText: '例如: ws://192.168.1.10:8080',
              controller: _urlController,
              keyboardType: TextInputType.url,
            ),
            // MAC地址字段改为只读显示
            _buildMacAddressDisplayField(),
            _buildTextFormField(
              label: 'Token',
              isRequired: false,
              hintText: '认证令牌（可选）',
              controller: _tokenController,
              obscureText: !_isTokenVisible,
              suffixIcon: Builder(
                builder: (context) {
                  final isDark = Theme.of(context).brightness == Brightness.dark;
                  return InkWell(
                    onTap: () {
                      setState(() {
                        _isTokenVisible = !_isTokenVisible;
                      });
                    },
                    child: Icon(
                      _isTokenVisible ? Icons.visibility_off : Icons.visibility,
                      color:
                          isDark ? const Color(0xFF757575) : Colors.grey.shade500,
                      size: 20,
                    ),
                  );
                },
              ),
            ),
            /* 🔒 隐藏 Dify 服务：else ...[
              // Dify服务字段
              _buildTextFormField(
                label: 'API地址',
                isRequired: true,
                hintText: 'https://api.dify.ai/v1',
                controller: _urlController,
                keyboardType: TextInputType.url,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '请输入API地址';
                  }
                  return null;
                },
              ),
              _buildTextFormField(
                label: 'API Key',
                isRequired: true,
                hintText: 'app-xxxxxxxxxxxx',
                controller: _apiKeyController,
                obscureText: true,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '请输入API Key';
                  }
                  return null;
                },
              ),
            ],
            */
          ],
        ),
      ),
    );
  }

  /// 构建说明卡片
  /// 蓝色背景（bg-blue-50），圆角16px，内边距16px
  /// 🔒 隐藏 Dify 服务：当前仅支持自定义服务
  Widget _buildInfoCard() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFF1E3A8A).withValues(alpha: 0.3)
              : const Color(0xFFEFF6FF), // blue-50
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark
                ? const Color(0xFF1E3A8A).withValues(alpha: 0.5)
                : const Color(0xFFDBEAFE),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题
            Row(
              children: [
                Text('💡', style: TextStyle(fontSize: 16, color: theme.colorScheme.onSurface)),
                const SizedBox(width: 8),
                Text(
                  '自定义服务说明',
                  // 🔒 隐藏 Dify 服务：_selectedServiceType == ServiceType.diy
                  //     ? '自定义服务说明'
                  //     : 'Dify服务说明',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isDark ? const Color(0xFF93C5FD) : const Color(0xFF1E3A8A), // blue-900
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // 说明文字
            Text(
              '自定义服务支持WebSocket协议连接。请确保服务器地址格式正确（ws://或wss://开头），MAC地址用于设备认证，Token用于安全验证。',
              // 🔒 隐藏 Dify 服务：_selectedServiceType == ServiceType.diy
              //     ? '自定义服务支持WebSocket协议连接。请确保服务器地址格式正确（ws://或wss://开头），MAC地址用于设备认证，Token用于安全验证。'
              //     : 'Dify服务需要提供有效的API地址和API Key。API Key可在Dify控制台获取，请确保密钥权限正确。',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? const Color(0xFF60A5FA) : const Color(0xFF1E40AF), // blue-700
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建添加服务按钮
  /// 全宽，黑色背景，圆角12px
  Widget _buildAddButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: _isSaving ? null : _saveService,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.grey.shade400,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
          shadowColor: Colors.transparent,
        ),
        child:
            _isSaving
                ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
                : const Text(
                  '添加服务',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
      ),
    );
  }

  /// 构建测试连接按钮
  /// 与添加按钮样式一致
  Widget _buildTestConnectionButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: _isTesting ? null : _testConnection,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.grey.shade400,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
          shadowColor: Colors.transparent,
        ),
        child:
            _isTesting
                ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
                : const Text(
                  '测试连接',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
      ),
    );
  }

  /// 测试WebSocket连接
  /// 🔒 隐藏 Dify 服务：当前仅支持自定义服务
  Future<void> _testConnection() async {
    // 🔒 隐藏 Dify 服务：仅对服务有效，当前仅支持自定义服务
    // if (_selectedServiceType != ServiceType.diy) {
    //   return;
    // }

    // 验证URL格式
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      _showTestResultSnackBar(success: false, message: '请输入服务器地址');
      return;
    }

    // 验证URL格式
    if (!url.startsWith('ws://') && !url.startsWith('wss://')) {
      _showTestResultSnackBar(
        success: false,
        message: '请输入有效的服务器地址（ws://或wss://开头）',
      );
      return;
    }

    setState(() {
      _isTesting = true;
    });

    // 先获取服务器配置信息进行协议检查
    final serverInfo = await getServerConfigInfo(
      serverUrl: url,
    );

    if (serverInfo != null) {
      final usesWss = url.startsWith('wss://');

      if (serverInfo.sslEnabled && !usesWss) {
        setState(() {
          _isTesting = false;
        });
        _showProtocolWarningDialog(
          expectedProtocol: 'wss://',
          actualProtocol: 'ws://',
          recommendation: serverInfo.message,
        );
        return;
      } else if (!serverInfo.sslEnabled && usesWss) {
        setState(() {
          _isTesting = false;
        });
        _showProtocolWarningDialog(
          expectedProtocol: 'ws://',
          actualProtocol: 'wss://',
          recommendation: serverInfo.message,
        );
        return;
      }
    }

    try {
      // 使用自动生成的MAC地址进行测试
      final macAddress = _generatedMacAddress ?? '00:00:00:00:00:00';
      final token = _tokenController.text.trim();

      // 调用连接测试服务
      final result = await testDiyConnection(
        serverUrl: url,
        macAddress: macAddress,
        token: token.isNotEmpty ? token : null,
      );

      // 显示测试结果
      _showTestResultSnackBar(
        success: result.success,
        message: result.message,
        handshakeTime: result.handshakeTime,
      );
    } catch (e) {
      _showTestResultSnackBar(success: false, message: '测试失败: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() {
          _isTesting = false;
        });
      }
    }
  }

  /// 显示协议不匹配警告对话框
  void _showProtocolWarningDialog({
    required String expectedProtocol,
    required String actualProtocol,
    required String recommendation,
  }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('协议不匹配'),
        content: Text(
          '检测到协议不匹配：\n\n'
          '您使用的是：$actualProtocol\n'
          '服务器推荐：$expectedProtocol\n\n'
          '$recommendation',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  /// 显示测试结果提示
  void _showTestResultSnackBar({
    required bool success,
    required String message,
    int? handshakeTime,
  }) {
    final backgroundColor =
        success ? Colors.green.shade600 : Colors.red.shade600;

    final icon =
        success
            ? const Icon(Icons.check_circle, color: Colors.white)
            : const Icon(Icons.cancel, color: Colors.white);

    final content =
        handshakeTime != null && success
            ? '$message (${handshakeTime}ms)'
            : message;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            icon,
            const SizedBox(width: 12),
            Expanded(child: Text(content)),
          ],
        ),
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  /// 构建固定底部按钮栏
  /// 🔒 隐藏 Dify 服务：当前仅支持自定义服务
  Widget _buildBottomBar() {
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
      child: Row(
        children: [
          // 测试连接按钮 - 🔒 隐藏 Dify 服务：当前仅支持自定义服务
          // if (_selectedServiceType == ServiceType.diy)
          Expanded(child: _buildTestConnectionButton()),
          // else
          //   const SizedBox.shrink(),
          // if (_selectedServiceType == ServiceType.diy) const SizedBox(width: 12),
          const SizedBox(width: 12),
          // 添加服务按钮
          Expanded(child: _buildAddButton()),
        ],
      ),
    );
  }
}

/// 服务类型枚举
/// 🔒 隐藏 Dify 服务：当前仅支持自定义服务
enum ServiceType {
  /// 自定义服务
  diy,

  /// 🔒 隐藏 Dify 服务：Dify服务
  // dify,
}
