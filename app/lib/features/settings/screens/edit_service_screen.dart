import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ai_assistant/core/providers/config_provider.dart';
import 'package:ai_assistant/core/models/diy_config.dart';
import 'package:ai_assistant/core/models/dify_config.dart';
import 'package:ai_assistant/core/models/icon_option.dart';
import 'package:ai_assistant/features/settings/providers/settings_provider.dart';
import 'package:ai_assistant/core/api/connection_tester.dart';

/// 编辑服务页面
///
/// 根据Figma设计实现：
/// - 自定义Header带返回按钮和标题
/// - 服务类型选择（只读，不可更改）
/// - 基础信息卡片（服务名称、服务类型）- 一行两列布局
/// - 服务器配置卡片（根据服务类型动态变化）- 一行两列布局
/// - 说明卡片（蓝色背景）
/// - 底部保存修改按钮（黑色背景，圆角12px）
class EditServiceScreen extends StatefulWidget {
  /// 自定义服务配置（编辑自定义服务时传入）
  final DiyConfig? diyConfig;

  /// Dify服务配置（编辑Dify服务时传入）
  final DifyConfig? difyConfig;

  const EditServiceScreen({
    super.key,
    this.diyConfig,
    this.difyConfig,
  }) : assert(
          diyConfig != null || difyConfig != null,
          '必须提供 diyConfig 或 difyConfig 之一',
        );

  @override
  State<EditServiceScreen> createState() => _EditServiceScreenState();
}

class _EditServiceScreenState extends State<EditServiceScreen> {
  /// 服务类型（从传入的配置确定，不可更改）
  late final ServiceType _serviceType;

  /// 选中的图标选项（初始化为当前配置的图标）
  late IconOption _selectedIcon;

  /// 表单控制器
  late final TextEditingController _nameController;
  late final TextEditingController _urlController;
  late final TextEditingController _macAddressController;
  late final TextEditingController _tokenController;
  late final TextEditingController _apiKeyController;

  /// 表单key
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  /// 是否正在保存
  bool _isSaving = false;

  /// Token是否可见
  bool _isTokenVisible = false;

  /// 服务器配置信息（用于协议检查）
  ServerConfigInfo? _serverConfigInfo;

  /// 是否正在测试连接
  bool _isTesting = false;

  @override
  void initState() {
    super.initState();

    // 确定服务类型并初始化控制器
    if (widget.diyConfig != null) {
      _serviceType = ServiceType.diy;
      _nameController = TextEditingController(text: widget.diyConfig!.name);
      _urlController = TextEditingController(text: widget.diyConfig!.websocketUrl);
      _macAddressController = TextEditingController(text: widget.diyConfig!.macAddress);
      _tokenController = TextEditingController(text: widget.diyConfig!.token);
      _apiKeyController = TextEditingController();

      /// 从现有配置中提取图标信息
      _selectedIcon = _findMatchingIconOption(
        widget.diyConfig!.icon.iconData,
        widget.diyConfig!.icon.backgroundColor,
        widget.diyConfig!.icon.iconColor,
      );
    } else {
      _serviceType = ServiceType.dify;
      _nameController = TextEditingController(text: widget.difyConfig!.name);
      _urlController = TextEditingController(text: widget.difyConfig!.apiUrl);
      _apiKeyController = TextEditingController(text: widget.difyConfig!.apiKey);
      _macAddressController = TextEditingController();
      _tokenController = TextEditingController();

      /// 从现有配置中提取图标信息
      _selectedIcon = _findMatchingIconOption(
        widget.difyConfig!.icon.iconData,
        widget.difyConfig!.icon.backgroundColor,
        widget.difyConfig!.icon.iconColor,
      );
    }
  }

  /// 根据图标数据查找匹配的IconOption
  IconOption _findMatchingIconOption(IconData iconData, Color bgColor, Color iconColor) {
    /// 尝试在预定义列表中查找匹配的图标
    for (final iconOption in availableIcons) {
      if (iconOption.icon == iconData &&
          iconOption.backgroundColor == bgColor &&
          iconOption.iconColor == iconColor) {
        return iconOption;
      }
    }

    /// 如果没有找到完全匹配的，查找图标匹配的选项
    for (final iconOption in availableIcons) {
      if (iconOption.icon == iconData) {
        return iconOption;
      }
    }

    /// 如果仍然没有找到，返回第一个选项作为默认值
    return availableIcons.first;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _macAddressController.dispose();
    _tokenController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  /// 验证并保存服务配置
  Future<void> _saveService() async {
    // 手动验证表单
    if (_nameController.text.trim().isEmpty) {
      _showErrorSnackBar('请输入服务名称');
      return;
    }
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      _showErrorSnackBar(_serviceType == ServiceType.diy ? '请输入服务器地址' : '请输入API地址');
      return;
    }

    // 根据服务类型进行不同的验证
    if (_serviceType == ServiceType.diy) {
      // 验证WebSocket URL格式
      final uri = Uri.tryParse(url);
      if (uri == null ||
          (!uri.hasScheme &&
              !url.startsWith('ws://') &&
              !url.startsWith('wss://'))) {
        _showErrorSnackBar('请输入有效的服务器地址（ws://或wss://开头）');
        return;
      }
    } else {
      // Dify服务：验证API Key
      if (_apiKeyController.text.trim().isEmpty) {
        _showErrorSnackBar('请输入API Key');
        return;
      }
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final configProvider = context.read<ConfigProvider>();
      final settingsProvider = context.read<SettingsProvider>();

      // 设置控制器值并调用更新方法
      if (_serviceType == ServiceType.diy) {
        settingsProvider.diyNameController.text = _nameController.text.trim();
        settingsProvider.diyWebsocketUrlController.text = _urlController.text.trim();
        // 保持原有的MAC地址，不允许修改
        settingsProvider.diyMacAddressController.text = widget.diyConfig!.macAddress;
        settingsProvider.diyTokenController.text = _tokenController.text.trim();

        /// 设置选中的图标
        settingsProvider.editingDiyIcon = _selectedIcon;

        await settingsProvider.updateDiyConfig(
          configProvider,
          widget.diyConfig!,
        );
      } else {
        settingsProvider.newDifyNameController.text = _nameController.text.trim();
        settingsProvider.newDifyApiUrlController.text = _urlController.text.trim();
        settingsProvider.newDifyApiKeyController.text = _apiKeyController.text.trim();

        /// 设置选中的图标
        settingsProvider.editingDifyIcon = _selectedIcon;

        await settingsProvider.updateDifyConfig(
          configProvider,
          widget.difyConfig!.id,
        );
      }

      if (mounted) {
        // 显示成功提示
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_serviceType == ServiceType.diy ? '自定义服务' : 'Dify服务'}已更新'),
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
        _showErrorSnackBar('更新失败: ${e.toString()}');
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
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
            '编辑服务',
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
            _buildFormField(
              label: '服务名称',
              isRequired: true,
              hintText: '例如：家庭助理',
              controller: _nameController,
            ),
            // 服务类型 - 一行两列布局，只读
            _buildServiceTypeField(),
            // 图标选择 - 新增字段
            _buildIconSelectorField(),
          ],
        ),
      ),
    );
  }

  /// 构建表单字段 - 一行两列布局
  /// 左侧：标签（固定宽度）
  /// 右侧：输入框（右对齐）
  Widget _buildFormField({
    required String label,
    required bool isRequired,
    required String hintText,
    required TextEditingController controller,
    bool obscureText = false,
    bool readOnly = false,
    TextInputType keyboardType = TextInputType.text,
    Widget? suffixIcon,
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
                  const Text(
                    '*',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFEF4444),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 16),
          // 右侧输入框 - 右对齐
          Expanded(
            child: SizedBox(
              height: 30,
              child: Align(
                alignment: Alignment.centerRight,
                child: TextFormField(
              controller: controller,
              obscureText: obscureText,
              keyboardType: keyboardType,
              textAlign: TextAlign.right,
              readOnly: readOnly,
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
                disabledBorder: InputBorder.none,
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
                color: readOnly
                    ? (isDark ? const Color(0xFFB0B0B0) : Colors.grey.shade600)
                    : theme.colorScheme.onSurface,
                height: 1.0,
              ),
            ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建服务类型字段 - 只读样式
  Widget _buildServiceTypeField() {
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 左侧标签 - 固定宽度
          SizedBox(
            width: 90,
            child: Row(
              children: [
                Text(
                  '服务类型',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(width: 2),
                const Text(
                  '*',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFEF4444),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // 右侧显示值（只读）
          Expanded(
            child: Text(
              _serviceType == ServiceType.diy ? '自定义服务' : 'Dify服务',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? const Color(0xFFB0B0B0) : Colors.grey.shade600,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建图标选择字段
  Widget _buildIconSelectorField() {
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
        onTap: () => _showIconPickerBottomSheet(),
        borderRadius: BorderRadius.circular(4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 左侧标签 - 固定宽度
            SizedBox(
              width: 90,
              child: Row(
                children: [
                  Text(
                    '图标',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            // 右侧显示值
            Expanded(
              child: Row(
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
                      color: theme.colorScheme.onSurface,
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
            ),
          ],
        ),
      ),
    );
  }

  /// 构建MAC地址显示字段（只读）
  Widget _buildMacAddressDisplayField() {
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
      child: Row(
        children: [
          // 左侧标签
          SizedBox(
            width: 90,
            child: Text(
              'MAC地址',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 16),
          // 右侧显示值
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                widget.diyConfig?.macAddress ?? '',
                style: TextStyle(
                  fontSize: 14,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

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
      builder: (context) => SafeArea(
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
              color: isDark ? const Color(0xFF3A3A3A) : const Color(0xFFE5E7EB),
            ),
            Container(
              height: 400,
              padding: const EdgeInsets.all(8),
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1,
                ),
                itemCount: availableIcons.length,
                itemBuilder: (context, index) {
                  final iconOption = availableIcons[index];
                  final bool isSelected = _selectedIcon.icon == iconOption.icon &&
                                       _selectedIcon.backgroundColor == iconOption.backgroundColor;

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
                        color: isSelected
                            ? iconOption.backgroundColor.withValues(alpha: 0.2)
                            : (isDark ? const Color(0xFF2A2A2A) : Colors.grey.shade100),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
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
                              color: isSelected
                                  ? iconOption.backgroundColor
                                  : (isDark ? const Color(0xFFB0B0B0) : Colors.grey.shade700),
                              fontWeight:
                                  isSelected ? FontWeight.bold : FontWeight.normal,
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
            if (_serviceType == ServiceType.diy) ...[
              // 自定义服务字段
              _buildFormField(
                label: '服务器地址',
                isRequired: true,
                hintText: '例如: ws://192.168.1.10:8080',
                controller: _urlController,
                keyboardType: TextInputType.url,
              ),
              // MAC地址字段改为只读显示
              _buildMacAddressDisplayField(),
              _buildFormField(
                label: 'Token',
                isRequired: false,
                hintText: '认证令牌（可选）',
                controller: _tokenController,
                obscureText: !_isTokenVisible,
                suffixIcon: InkWell(
                  onTap: () {
                    setState(() {
                      _isTokenVisible = !_isTokenVisible;
                    });
                  },
                  child: Icon(
                    _isTokenVisible ? Icons.visibility_off : Icons.visibility,
                    color: Colors.grey.shade500,
                    size: 20,
                  ),
                ),
              ),
            ] else ...[
              // Dify服务字段
              _buildFormField(
                label: 'API地址',
                isRequired: true,
                hintText: 'https://api.dify.ai/v1',
                controller: _urlController,
                keyboardType: TextInputType.url,
              ),
              _buildFormField(
                label: 'API Key',
                isRequired: true,
                hintText: 'app-xxxxxxxxxxxx',
                controller: _apiKeyController,
                obscureText: true,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 构建说明卡片
  /// 蓝色背景（bg-blue-50），圆角16px，内边距16px
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
                Text(
                  '💡',
                  style: TextStyle(fontSize: 16, color: theme.colorScheme.onSurface),
                ),
                const SizedBox(width: 8),
                Text(
                  _serviceType == ServiceType.diy ? '自定义服务说明' : 'Dify服务说明',
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
              _serviceType == ServiceType.diy
                  ? '自定义服务支持WebSocket协议连接。请确保服务器地址格式正确（ws://或wss://开头），MAC地址用于设备认证，Token用于安全验证。'
                  : 'Dify服务需要提供有效的API地址和API Key。API Key可在Dify控制台获取，请确保密钥权限正确。',
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

  /// 构建保存修改按钮
  /// 全宽，黑色背景，圆角12px
  Widget _buildSaveButton() {
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
        child: _isSaving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Text(
                '保存修改',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
      ),
    );
  }

  /// 构建测试连接按钮
  /// 与保存按钮样式一致
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
        child: _isTesting
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

  /// 构建固定底部按钮栏
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
          // 测试连接按钮（仅自定义服务）
          if (_serviceType == ServiceType.diy)
            Expanded(child: _buildTestConnectionButton())
          else
            const SizedBox.shrink(),
          if (_serviceType == ServiceType.diy) const SizedBox(width: 12),
          // 保存修改按钮
          Expanded(child: _buildSaveButton()),
        ],
      ),
    );
  }

  /// 测试WebSocket连接（仅自定义服务）
  Future<void> _testConnection() async {
    if (_serviceType != ServiceType.diy) {
      return;
    }

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
      // 使用配置中的MAC地址进行测试
      final macAddress = widget.diyConfig?.macAddress ?? '00:00:00:00:00:00';
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
}

/// 服务类型枚举
enum ServiceType {
  /// 自定义服务
  diy,
  /// Dify服务
  dify,
}
