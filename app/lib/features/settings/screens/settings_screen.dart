import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ai_assistant/features/settings/providers/settings_provider.dart';
import 'package:ai_assistant/features/settings/screens/server_settings_screen.dart';
import 'package:ai_assistant/features/settings/screens/general_settings_screen.dart';
import 'package:ai_assistant/features/settings/screens/model_settings_screen.dart';
import 'package:ai_assistant/features/settings/about/about_screen.dart';

/// 设置页面主入口
///
/// 采用卡片式导航设计，包含两个主要入口卡片：
/// - 服务配置（包含服务器设置和模型设置）
/// - 通用设置（紫色渐变图标）
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SettingsProvider(),
      child: const _SettingsScreenContent(),
    );
  }
}

class _SettingsScreenContent extends StatelessWidget {
  const _SettingsScreenContent();

  /// 导航到服务器设置页面
  void _navigateToServerSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const ServerSettingsScreen()),
    );
  }

  /// 导航到通用设置页面
  void _navigateToGeneralSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const GeneralSettingsScreen()),
    );
  }

  /// 导航到模型设置页面
  void _navigateToModelSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const ModelSettingsScreen()),
    );
  }

  /// 导航到关于页面
  void _navigateToAbout(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const AboutScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(
          '设置',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
        ),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 64,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: isDark ? const Color(0xFF3A3A3A) : const Color(0xFFE5E7EB),
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              const SizedBox(height: 8),
              _buildServiceConfigCard(context),
              const SizedBox(height: 12),
              _buildGeneralSettingsCard(context),
              const SizedBox(height: 12),
              _buildAboutCard(context),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建服务配置卡片
  ///
  /// 包含服务器设置和模型设置两个子项
  Widget _buildServiceConfigCard(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      borderRadius: BorderRadius.circular(16),
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 服务器设置项
            _buildSettingsItem(
              context,
              icon: Icons.cloud_outlined,
              iconGradient: const LinearGradient(
                colors: [Color(0xFF4A90E2), Color(0xFF357ABD)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              title: '服务器设置',
              subtitle: '管理自定义服务配置',
              onTap: () => _navigateToServerSettings(context),
            ),
            // 分割线
            Padding(
              padding: const EdgeInsets.only(left: 80, right: 16),
              child: Divider(
                height: 1,
                color: isDark ? const Color(0xFF3A3A3A) : Colors.grey.shade200,
              ),
            ),
            // 模型设置项
            _buildSettingsItem(
              context,
              icon: Icons.tune_outlined,
              iconGradient: const LinearGradient(
                colors: [Color(0xFF10B981), Color(0xFF059669)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              title: '模型设置',
              subtitle: '配置各服务器的AI模型',
              onTap: () => _navigateToModelSettings(context),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建通用设置卡片
  ///
  /// 使用紫色渐变图标，点击后进入通用设置页面
  Widget _buildGeneralSettingsCard(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? const Color(0xFF3A3A3A) : Colors.grey.shade200,
            width: 1,
          ),
        ),
        child: InkWell(
          onTap: () => _navigateToGeneralSettings(context),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // 渐变图标背景
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF9B59B6), Color(0xFF8E44AD)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.settings_outlined,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 16),
                // 标题和副标题
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '通用设置',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '应用外观、语言和通知',
                        style: TextStyle(
                          fontSize: 13,
                          color:
                              isDark
                                  ? const Color(0xFFB0B0B0)
                                  : const Color(0xFF757575),
                        ),
                      ),
                    ],
                  ),
                ),
                // 右箭头
                Icon(
                  Icons.chevron_right,
                  color:
                      isDark ? const Color(0xFF757575) : Colors.grey.shade400,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 构建关于卡片
  ///
  /// 使用灰蓝色渐变图标，点击后进入关于页面
  Widget _buildAboutCard(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? const Color(0xFF3A3A3A) : Colors.grey.shade200,
            width: 1,
          ),
        ),
        child: InkWell(
          onTap: () => _navigateToAbout(context),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // 渐变图标背景
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF64748B), Color(0xFF475569)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.info_outline_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                // 标题和副标题
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '关于',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '版本信息、隐私政策、联系我们',
                        style: TextStyle(
                          fontSize: 13,
                          color:
                              isDark
                                  ? const Color(0xFFB0B0B0)
                                  : const Color(0xFF757575),
                        ),
                      ),
                    ],
                  ),
                ),
                // 右箭头
                Icon(
                  Icons.chevron_right,
                  color:
                      isDark ? const Color(0xFF757575) : Colors.grey.shade400,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 构建设置子项
  ///
  /// 用于服务配置卡片中的子项样式，包含渐变图标、标题和副标题
  Widget _buildSettingsItem(
    BuildContext context, {
    required IconData icon,
    required Gradient iconGradient,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // 渐变图标背景
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: iconGradient,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            // 标题和副标题
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color:
                          isDark
                              ? const Color(0xFFB0B0B0)
                              : Colors.grey.shade600,
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
    );
  }
}
