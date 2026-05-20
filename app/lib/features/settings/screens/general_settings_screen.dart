import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ai_assistant/core/config/theme_provider.dart';
import 'package:ai_assistant/features/settings/widgets/settings_app_bar.dart';

/// 通用设置页面
///
/// 包含应用外观和语言设置
class GeneralSettingsScreen extends StatelessWidget {
  const GeneralSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            // 使用统一的TopBar组件
            SettingsAppBar(title: '通用设置'),
            // 内容区域
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: const [
                  _BackgroundSettingCard(),
                  SizedBox(height: 12),
                  _LanguageSettingCard(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 背景设置卡片
///
/// 支持跟随系统、浅色模式和深色模式三种选项
class _BackgroundSettingCard extends StatelessWidget {
  const _BackgroundSettingCard();

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return _buildSettingCard(
          context: context,
          icon: Icons.palette_outlined,
          iconGradient: const LinearGradient(
            colors: [Color(0xFF757575), Color(0xFF616161)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          title: '背景设置',
          subtitle: themeProvider.themeModeName,
          trailing: DropdownButton<ThemeMode>(
            value: themeProvider.themeMode,
          icon: Icon(Icons.keyboard_arrow_down, color: Theme.of(context).colorScheme.onSurface),
            iconSize: 24,
            elevation: 16,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 14,
            ),
            underline: const SizedBox.shrink(),
            dropdownColor: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF1E1E1E)
                : Colors.white,
            onChanged: (ThemeMode? newValue) {
              if (newValue != null) {
                themeProvider.setThemeMode(newValue);
              }
            },
            items: [
              DropdownMenuItem(
                value: ThemeMode.system,
                child: Row(
                  children: [
                    Icon(Icons.brightness_auto, size: 20, color: Theme.of(context).colorScheme.onSurface),
                    const SizedBox(width: 8),
                    Text('跟随系统', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                  ],
                ),
              ),
              DropdownMenuItem(
                value: ThemeMode.light,
                child: Row(
                  children: [
                    Icon(Icons.light_mode, size: 20, color: Theme.of(context).colorScheme.onSurface),
                    const SizedBox(width: 8),
                    Text('浅色模式', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                  ],
                ),
              ),
              DropdownMenuItem(
                value: ThemeMode.dark,
                child: Row(
                  children: [
                    Icon(Icons.dark_mode, size: 20, color: Theme.of(context).colorScheme.onSurface),
                    const SizedBox(width: 8),
                    Text('深色模式', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 语言设置卡片
///
/// 使用绿色渐变图标，当前仅支持简体中文
class _LanguageSettingCard extends StatelessWidget {
  const _LanguageSettingCard();

  @override
  Widget build(BuildContext context) {
    return _buildSettingCard(
      context: context,
      icon: Icons.language_outlined,
      iconGradient: const LinearGradient(
        colors: [Color(0xFF66BB6A), Color(0xFF4CAF50)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      title: '语言',
      subtitle: '简体中文',
      trailing: Icon(
        Icons.chevron_right,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// 统一的设置卡片构建方法
///
/// 创建带有渐变图标的设置卡片
Widget _buildSettingCard({
  required BuildContext context,
  required IconData icon,
  required Gradient iconGradient,
  required String title,
  required String subtitle,
  required Widget trailing,
}) {
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;

  return Container(
    padding: const EdgeInsets.all(12),
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
        // 渐变图标背景
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: iconGradient,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
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
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? const Color(0xFFB0B0B0) : Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
        // 右侧控件（Switch或Dropdown）
        trailing,
      ],
    ),
  );
}
