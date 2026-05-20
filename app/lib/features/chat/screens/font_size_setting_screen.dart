import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 文字大小设置页面
/// 参考设计：滑动条调节字体大小，带预览功能
class FontSizeSettingScreen extends StatefulWidget {
  final String conversationId;

  const FontSizeSettingScreen({
    required this.conversationId,
    super.key,
  });

  @override
  State<FontSizeSettingScreen> createState() => _FontSizeSettingScreenState();
}

class _FontSizeSettingScreenState extends State<FontSizeSettingScreen> {
  // 字体大小范围 12 - 24，默认 16
  double _currentFontSize = 16.0;

  @override
  void initState() {
    super.initState();
    // 从 SharedPreferences 加载当前字体大小
    _loadFontSize();
  }

  Future<void> _loadFontSize() async {
    final prefs = await SharedPreferences.getInstance();
    final fontSize = prefs.getDouble('chat_font_size_${widget.conversationId}');
    if (fontSize != null && mounted) {
      setState(() {
        _currentFontSize = fontSize;
      });
    }
  }

  Future<void> _saveFontSize() async {
    // 保存到 SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('chat_font_size_${widget.conversationId}', _currentFontSize);

    if (mounted) {
      // 返回新的字体大小值，让调用者知道字体已更改
      Navigator.of(context).pop(_currentFontSize);
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
            _buildHeader(theme),
            Container(
              height: 1,
              color: isDark ? const Color(0xFF3A3A3A) : const Color(0xFFE5E7EB),
            ),
            // 固定在顶部的滑动条控制区（不随页面滚动）
            Container(
              color: theme.colorScheme.surface,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                children: [
                  // 标题行
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '字体大小',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        '${_currentFontSize.toInt()}',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 滑动条
                  SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 4,
                      activeTrackColor: Colors.blue.shade600,
                      inactiveTrackColor: isDark ? const Color(0xFF3A3A3A) : const Color(0xFFE5E7EB),
                      thumbColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                      overlayColor: Colors.blue.shade600.withValues(alpha: 0.12),
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 12,
                      ),
                    ),
                    child: Slider(
                      value: _currentFontSize,
                      min: 12,
                      max: 24,
                      divisions: 12,
                      onChanged: (value) {
                        setState(() {
                          _currentFontSize = value;
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 8),

                  // 最小/最大标签
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'A',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? const Color(0xFF757575) : Colors.grey.shade600,
                        ),
                      ),
                      Text(
                        '标准',
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? const Color(0xFF757575) : Colors.grey.shade600,
                        ),
                      ),
                      Text(
                        'A',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark ? const Color(0xFF757575) : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // 分隔线
            Container(
              height: 1,
              color: isDark ? const Color(0xFF3A3A3A) : const Color(0xFFE5E7EB),
            ),

            // 可滚动的预览区域
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    const SizedBox(height: 16),

                    // 预览示例区域（始终显示）
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: isDark ? const Color(0xFF3A3A3A) : const Color(0xFFE5E7EB)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '预览示例',
                            style: TextStyle(
                              fontSize: _currentFontSize * 0.9,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 16),
                          _buildPreviewMessage(),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建自定义Header
  Widget _buildHeader(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      color: theme.colorScheme.surface,
      child: Row(
        children: [
          // 取消按钮
          InkWell(
            onTap: () => Navigator.of(context).pop(),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.all(8),
              child: Text(
                '取消',
                style: TextStyle(
                  fontSize: 16,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // 标题
          Expanded(
            child: Text(
              '文字大小',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 12),
          // 确认按钮
          InkWell(
            onTap: _saveFontSize,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.all(8),
              child: Text(
                '确认',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.blue.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 预览消息示例
  Widget _buildPreviewMessage() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // AI 消息
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: const Color(0xFF10B981),
                    child: const Icon(Icons.smart_toy, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'AI助手',
                    style: TextStyle(
                      fontSize: _currentFontSize * 0.8,
                      fontWeight: FontWeight.w500,
                      color: isDark ? const Color(0xFFB0B0B0) : const Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '你好！这是一段示例文本，用于预览当前字体大小的显示效果。',
                style: TextStyle(
                  fontSize: _currentFontSize,
                  color: theme.colorScheme.onSurface,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // 用户消息
        Align(
          alignment: Alignment.centerRight,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade600,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '字体大小调整功能',
              style: TextStyle(
                fontSize: _currentFontSize,
                color: Colors.white,
                height: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
