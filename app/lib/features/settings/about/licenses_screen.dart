import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

/// 开源许可证页面
///
/// 展示应用使用的开源软件许可证信息
class LicensesScreen extends StatelessWidget {
  const LicensesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(
          '开源许可证',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
        ),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        child: FutureBuilder<List<LicenseEntry>>(
          future: LicenseRegistry.licenses.toList(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(),
              );
            }

            if (snapshot.hasError) {
              return Center(
                child: Text('加载失败: ${snapshot.error}'),
              );
            }

            final licenses = snapshot.data ?? [];

            if (licenses.isEmpty) {
              return const Center(
                child: Text('暂无许可证信息'),
              );
            }

            // 按包名分组并排序
            final packages = <String>{};
            for (final license in licenses) {
              for (final package in license.packages) {
                packages.add(package);
              }
            }
            final sortedPackages = packages.toList()..sort();

            return ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: sortedPackages.length,
              itemBuilder: (context, index) {
                final package = sortedPackages[index];
                return _LicenseTile(packageName: package);
              },
            );
          },
        ),
      ),
    );
  }
}

/// 许可证列表项
class _LicenseTile extends StatefulWidget {
  final String packageName;

  const _LicenseTile({required this.packageName});

  @override
  State<_LicenseTile> createState() => _LicenseTileState();
}

class _LicenseTileState extends State<_LicenseTile> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              setState(() {
                _isExpanded = !_isExpanded;
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    size: 20,
                    color: theme.primaryColor,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.packageName,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  Icon(
                    _isExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: isDark ? const Color(0xFF666666) : Colors.grey,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_isExpanded)
          Container(
            margin: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: FutureBuilder<List<LicenseEntry>>(
              future: LicenseRegistry.licenses.toList(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const SizedBox.shrink();
                }

                final relevantLicenses = snapshot.data!
                    .where((license) => license.packages.contains(widget.packageName))
                    .toList();

                final paragraphs = <String>[];
                for (final license in relevantLicenses) {
                  for (final paragraph in license.paragraphs) {
                    paragraphs.add(paragraph.text);
                  }
                }

                if (paragraphs.isEmpty) {
                  return const Text('无许可证文本');
                }

                return SelectableText(
                  paragraphs.join('\n\n'),
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    fontFamily: 'monospace',
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                  ),
                );
              },
            ),
          ),
        Divider(
          height: 1,
          indent: 16,
          endIndent: 16,
          color: isDark ? const Color(0xFF2A2A2A) : Colors.grey.shade200,
        ),
      ],
    );
  }
}
