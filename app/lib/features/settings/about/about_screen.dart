import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:ai_assistant/features/settings/about/privacy_policy_screen.dart';

/// 关于页面
///
/// 展示应用信息、隐私政策、开源许可证、联系方式等
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  PackageInfo? _packageInfo;
  bool _isCheckingUpdate = false;

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
  }

  Future<void> _loadPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _packageInfo = info;
      });
    }
  }

  /// 打开隐私政策页面
  void _navigateToPrivacyPolicy() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const PrivacyPolicyScreen()),
    );
  }

  /// 检查更新
  Future<void> _checkForUpdate() async {
    setState(() {
      _isCheckingUpdate = true;
    });

    // TODO: 对接应用商店API或自定义服务器检查更新
    await Future.delayed(const Duration(seconds: 1));

    if (mounted) {
      setState(() {
        _isCheckingUpdate = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('当前已是最新版本'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// 打开联系邮箱
  Future<void> _openEmail() async {
    final uri = Uri(
      scheme: 'mailto',
      path: 'lingzhi0211@163.com',
      query: _encodeQueryParameters({'subject': '零知 用户反馈'}),
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('无法打开邮件应用')));
      }
    }
  }

  /// 打开GitHub仓库
  Future<void> _openGitHub() async {
    const url = 'https://github.com/nephilimbin/lingzhi';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('无法打开链接')));
      }
    }
  }

  String? _encodeQueryParameters(Map<String, String> params) {
    return params.entries
        .map(
          (e) =>
              '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
        )
        .join('&');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(
          '关于',
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              physics: constraints.maxHeight > 600
                  ? const NeverScrollableScrollPhysics()
                  : null,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        children: [
                          const SizedBox(height: 24),
                          // 应用图标和名称
                          _buildAppHeader(theme),
                          const SizedBox(height: 32),
                          // 基础信息卡片
                          _buildInfoCard(theme, isDark),
                          const SizedBox(height: 12),
                          // 联系方式卡片
                          _buildContactCard(theme, isDark),
                        ],
                      ),
                      const SizedBox(height: 24),
                      // ICP备案信息
                      _buildIcpInfo(theme),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// 构建ICP备案信息
  Widget _buildIcpInfo(ThemeData theme) {
    return Text(
      'ICP备案号: 津ICP备2026001955号-2A',
      style: TextStyle(
        fontSize: 12,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
      ),
      textAlign: TextAlign.center,
    );
  }

  /// 构建应用头部信息
  Widget _buildAppHeader(ThemeData theme) {
    return Column(
      children: [
        // 应用图标
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: theme.primaryColor.withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Image.asset(
              'assets/lingzhi_logo.jpg',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  color: theme.primaryColor,
                  child: Icon(
                    Icons.smart_toy_outlined,
                    size: 40,
                    color: Colors.white,
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 16),
        // 应用名称
        Text(
          '零知',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        // 版本号
        Text(
          _packageInfo != null ? '版本 ${_packageInfo!.version}' : '加载中...',
          style: TextStyle(
            fontSize: 14,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  /// 构建基础信息卡片
  Widget _buildInfoCard(ThemeData theme, bool isDark) {
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
            _AboutListTile(
              icon: Icons.privacy_tip_outlined,
              iconGradient: const LinearGradient(
                colors: [Color(0xFF4A90E2), Color(0xFF357ABD)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              title: '隐私政策',
              onTap: _navigateToPrivacyPolicy,
            ),
            _buildDivider(isDark),
            _AboutListTile(
              icon: Icons.system_update_outlined,
              iconGradient: const LinearGradient(
                colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              title: '检查更新',
              trailing:
                  _isCheckingUpdate
                      ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : null,
              onTap: _isCheckingUpdate ? null : _checkForUpdate,
            ),
          ],
        ),
      ),
    );
  }

  /// 构建联系方式卡片
  Widget _buildContactCard(ThemeData theme, bool isDark) {
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
            _AboutListTile(
              icon: Icons.email_outlined,
              iconGradient: const LinearGradient(
                colors: [Color(0xFFEC4899), Color(0xFFDB2777)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              title: '联系作者',
              subtitle: 'lingzhi0211@163.com',
              onTap: _openEmail,
            ),
            _buildDivider(isDark),
            _AboutListTile(
              icon: Icons.code_outlined,
              iconGradient: const LinearGradient(
                colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              title: 'GitHub 仓库',
              subtitle: 'github.com/nephilimbin/lingzhi',
              onTap: _openGitHub,
            ),
          ],
        ),
      ),
    );
  }

  /// 构建分割线
  Widget _buildDivider(bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(left: 80, right: 16),
      child: Divider(
        height: 1,
        color: isDark ? const Color(0xFF3A3A3A) : Colors.grey.shade200,
      ),
    );
  }
}

/// 关于页面列表项
class _AboutListTile extends StatelessWidget {
  final IconData icon;
  final Gradient iconGradient;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _AboutListTile({
    required this.icon,
    required this.iconGradient,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
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
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color:
                          onTap == null
                              ? theme.colorScheme.onSurface.withValues(
                                alpha: 0.5,
                              )
                              : theme.colorScheme.onSurface,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 13,
                        color:
                            isDark
                                ? const Color(0xFFB0B0B0)
                                : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            trailing ??
                Icon(
                  Icons.chevron_right,
                  color:
                      isDark ? const Color(0xFF757575) : Colors.grey.shade400,
                  size: 20,
                ),
          ],
        ),
      ),
    );
  }
}
