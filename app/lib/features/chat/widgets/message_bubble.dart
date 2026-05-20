import 'dart:math';
import 'dart:io';

import 'package:ai_assistant/core/config/app_theme.dart';
import 'package:ai_assistant/core/models/message.dart';
import 'package:ai_assistant/core/models/conversation.dart';
import 'package:ai_assistant/features/chat/providers/chat_provider.dart';
import 'package:ai_assistant/features/chat/widgets/code_block_builder.dart';
import 'package:ai_assistant/features/chat/widgets/latex_render_utils.dart';
import 'package:ai_assistant/features/chat/widgets/mixed_content_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

class MessageBubble extends StatelessWidget {
  final Message message;
  final bool isThinking;
  final ConversationType? conversationType;

  const MessageBubble({
    required this.message,
    super.key,
    this.isThinking = false,
    this.conversationType,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;
    final isSystem = message.role == MessageRole.system;

    // 从 ChatProvider 获取字体大小，默认 15
    final chatProvider = Provider.of<ChatProvider>(context, listen: true);
    final messageFontSize = chatProvider.fontSize ?? 15.0;

    // 系统消息使用不同的展示方式
    if (isSystem) {
      return _buildSystemMessage(context);
    }

    // 使用更高效的布局
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 用户消息 - 右对齐，限制最大宽度，预留右边距
          if (isUser)
            Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.9,
              ),
              child: _buildMessageBubble(
                context,
                messageFontSize,
                isUser: true,
              ),
            )
          // 助手消息 - 左对齐，占满剩余空间
          else
            Expanded(
              child: _buildMessageBubble(
                context,
                messageFontSize,
                isUser: false,
              ),
            ),
        ],
      ),
    );
  }

  // 统一的消息气泡构建方法
  Widget _buildMessageBubble(
    BuildContext context,
    double messageFontSize, {
    required bool isUser,
  }) {
    return Container(
      padding: message.isImage
          ? const EdgeInsets.all(4)
          : const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 10,
            ),
      decoration: BoxDecoration(
        color: isUser
            ? getUserMessageBubbleColor()
            : getAssistantMessageBubbleColor(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          // 用户消息：直接显示内容
          if (isUser)
            Text(
              message.content,
              style: TextStyle(
                color: getUserMessageTextColor(),
                fontSize: messageFontSize,
                height: 1.4,
                leadingDistribution: TextLeadingDistribution.even,
              ),
            )
          // 助手图片消息：显示图片
          else if (message.isImage)
            _buildImageContent(context)
          // 助手消息：显示文字内容或等待气泡
          else if (!isUser) ...[
            // 如果有实际内容，显示文字内容
            if (message.content.isNotEmpty)
              _buildAssistantMessage(context, messageFontSize),
            // 如果是等待状态，显示等待气泡
            if (isThinking && message.content.isEmpty)
              _buildThinkingIndicator(context),
          ],
        ],
      ),
    );
  }

  Widget _buildImageContent(BuildContext context) {
    final isUser = message.role == MessageRole.user;

    if (message.imageLocalPath != null && message.imageLocalPath!.isNotEmpty) {
      final imageFile = File(message.imageLocalPath!);
      if (!imageFile.existsSync()) {
        return _buildImagePlaceholder(context, isUser, "图片已被删除");
      }

      return Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              imageFile,
              width: 200,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return _buildImagePlaceholder(context, isUser, "图片加载失败");
              },
            ),
          ),
          if (message.content.isNotEmpty &&
              !message.content.startsWith("[图片上传中"))
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 8, right: 8),
              child: Text(
                message.content,
                style: TextStyle(
                  color:
                      isUser
                          ? Theme.of(context).colorScheme.onPrimary
                          : Theme.of(context).colorScheme.onSecondaryContainer,
                  fontSize: 13,
                ),
              ),
            ),
        ],
      );
    }

    return _buildImagePlaceholder(context, isUser, message.content);
  }

  Widget _buildImagePlaceholder(
    BuildContext context,
    bool isUser,
    String text,
  ) {
    final theme = Theme.of(context);
    final color =
        isUser
            ? theme.colorScheme.onPrimary.withValues(alpha: 0.7)
            : theme.colorScheme.onSecondaryContainer.withValues(alpha: 0.7);

    return Container(
      padding: const EdgeInsets.all(8),
      width: 150,
      height: 150,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.image_not_supported, color: color, size: 40),
            const SizedBox(height: 8),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: color, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThinkingIndicator(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildPulsatingDot(context, 0),
        _buildPulsatingDot(context, 1),
        _buildPulsatingDot(context, 2),
      ],
    );
  }

  Widget _buildPulsatingDot(BuildContext context, int index) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      child: _ThinkingDot(index: index, color: Colors.grey.shade600),
    );
  }

  // 构建助手消息，支持长按功能、Markdown渲染和LaTeX公式渲染
  Widget _buildAssistantMessage(BuildContext context, double messageFontSize) {
    // 预处理内容，优化流式响应时的 markdown 渲染
    String processedContent = _preprocessMarkdownContent(message.content);

    // 检查内容是否包含 LaTeX 公式
    final bool hasLatex = LatexRenderUtils.containsLatex(processedContent);

    return GestureDetector(
      onLongPress: () => _showMessageOptions(context),
      child: hasLatex
          ? _buildMixedContent(processedContent, context, messageFontSize)
          : _buildMarkdownContent(processedContent, context, messageFontSize),
    );
  }

  /// 构建纯 Markdown 内容（不包含公式）
  Widget _buildMarkdownContent(
    String content,
    BuildContext context,
    double messageFontSize,
  ) {
    return MarkdownBody(
      data: content,
      selectable: true,
      extensionSet: md.ExtensionSet.gitHubFlavored,
      builders: {'code': CustomCodeBlockBuilder(context: context)},
      styleSheet: _createOptimizedMarkdownStyleSheet(context, messageFontSize),
      onTapLink: (text, href, title) => _handleLinkTap(href),
    );
  }

  /// 构建混合内容（Markdown + LaTeX）
  Widget _buildMixedContent(
    String content,
    BuildContext context,
    double messageFontSize,
  ) {
    return MixedContentWidget(
      content: content,
      selectable: true,
      styleSheet: _createOptimizedMarkdownStyleSheet(context, messageFontSize),
      extensionSet: md.ExtensionSet.gitHubFlavored,
      builders: {'code': CustomCodeBlockBuilder(context: context)},
      onTapLink: (text, href, title) => _handleLinkTap(href),
    );
  }

  /// 处理链接点击
  void _handleLinkTap(String? href) async {
    if (href == null) {
      return;
    }
    final uri = Uri.tryParse(href);
    if (uri != null) {
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (e) {
        debugPrint('打开链接失败: $e');
      }
    }
  }

  // 预处理 markdown 内容，优化流式响应时的显示
  String _preprocessMarkdownContent(String content) {
    if (content.trim().isEmpty) {
      return content;
    }

    // 处理换行符：确保单个\n能正确换行
    String processedContent = _handleLineBreaks(content);

    // 处理波浪号与删除线语法的冲突
    processedContent = _handleStrikethroughConflicts(processedContent);

    return processedContent;
  }

  // 处理换行符，确保单个\n能正确换行
  String _handleLineBreaks(String content) {
    // 在单个换行符后添加两个空格，确保Markdown能正确换行
    // 但保持段落间的双换行符不变
    return content
        .replaceAllMapped(RegExp(r'(?<!\n)\n(?!\n)'), (match) => '  \n');
  }

  // 专门处理删除线语法与波浪号的冲突
  String _handleStrikethroughConflicts(String content) {
    // 保护完整的删除线语法 ~~text~~，避免单独的波浪号被转义
    final List<String> protectedStrikethroughs = [];
    String tempContent = content;

    // 使用正则表达式匹配完整的删除线语法
    final strikethroughRegex = RegExp(r'~~[^~]+~~');
    int matchCount = 0;

    // 临时替换所有删除线语法
    tempContent = tempContent.replaceAllMapped(strikethroughRegex, (match) {
      final placeholder = '__STRIKETHROUGH_${matchCount}__';
      protectedStrikethroughs.add(match.group(0)!);
      matchCount++;
      return placeholder;
    });

    // 转义剩余的单独波浪号（非删除线语法）
    tempContent = tempContent.replaceAll('~', '\\~');

    // 恢复保护的删除线语法
    for (int i = 0; i < protectedStrikethroughs.length; i++) {
      tempContent = tempContent.replaceAll('__STRIKETHROUGH_${i}__', protectedStrikethroughs[i]);
    }

    return tempContent;
  }


  // 创建优化的 markdown 样式表
  MarkdownStyleSheet _createOptimizedMarkdownStyleSheet(BuildContext context, double messageFontSize) {
    // 根据基础字体大小计算其他样式大小
    final baseSize = messageFontSize;
    final h1Size = baseSize * 1.33;
    final h2Size = baseSize * 1.2;
    final h3Size = baseSize * 1.07;
    final codeSize = baseSize * 0.87;
    final smallSize = baseSize * 0.93;

    // 根据主题模式选择颜色
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? const Color(0xFFE0E0E0) : Colors.black87;
    final strongColor = isDark ? Colors.white : Colors.black;
    final codeBgColor = isDark ? const Color(0xFF3A3A3A) : Colors.grey.shade200;
    final blockquoteBgColor = isDark ? const Color(0xFF2A2A2A) : Colors.grey.shade50;
    final blockquoteBorderColor = isDark ? const Color(0xFF4A4A4A) : Colors.grey.shade400;

    return MarkdownStyleSheet(
      // 段落样式 - 优化行高和间距
      p: TextStyle(
        fontSize: baseSize,
        color: textColor,
        height: 1.5, // 增加行高，提高可读性
        leadingDistribution: TextLeadingDistribution.even,
      ),

      // 标题样式 - 优化层次和间距
      h1: TextStyle(
        fontSize: h1Size,
        color: textColor,
        fontWeight: FontWeight.bold,
        height: 1.3,
      ),
      h2: TextStyle(
        fontSize: h2Size,
        color: textColor,
        fontWeight: FontWeight.bold,
        height: 1.3,
      ),
      h3: TextStyle(
        fontSize: h3Size,
        color: textColor,
        fontWeight: FontWeight.bold,
        height: 1.3,
      ),

      // 粗体样式 - 确保在流式渲染中也能正确显示
      strong: TextStyle(
        fontWeight: FontWeight.w700,
        color: strongColor,
        fontSize: baseSize,
      ),

      // 斜体样式
      em: TextStyle(fontStyle: FontStyle.italic, color: textColor),

      // 列表样式 - 优化数字列表和无序列表的显示
      listBullet: TextStyle(
        fontSize: baseSize,
        color: textColor,
        height: 1.5,
      ),
      listIndent: 32, // 增加缩进，使列表结构更清晰
      listBulletPadding: const EdgeInsets.only(right: 8),

      // 引用样式
      blockquote: TextStyle(
        fontSize: smallSize,
        color: isDark ? const Color(0xFFB0B0B0) : Colors.grey.shade700,
        fontStyle: FontStyle.italic,
        height: 1.4,
      ),
      blockquoteDecoration: BoxDecoration(
        color: blockquoteBgColor,
        border: Border(left: BorderSide(color: blockquoteBorderColor, width: 3)),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(4),
          bottomRight: Radius.circular(4),
        ),
      ),
      blockquotePadding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 8,
      ),

      // 内联代码样式
      code: TextStyle(
        fontSize: codeSize,
        backgroundColor: codeBgColor,
        color: isDark ? const Color(0xFFE06C75) : Colors.red.shade700,
        fontFamily: 'Courier',
        letterSpacing: 0.3,
      ),

      // 代码块样式 - 使用自定义组件
      codeblockDecoration: const BoxDecoration(color: Colors.transparent),
      codeblockPadding: EdgeInsets.zero,

      // 表格样式
      tableHead: TextStyle(
        fontWeight: FontWeight.bold,
        color: textColor,
        fontSize: smallSize,
      ),
      tableBody: TextStyle(color: textColor, fontSize: smallSize),
      tableBorder: TableBorder.all(
        color: isDark ? const Color(0xFF3A3A3A) : Colors.grey.shade300,
        width: 1,
        borderRadius: BorderRadius.circular(4),
      ),

      // 水平分割线
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(width: 1, color: isDark ? const Color(0xFF3A3A3A) : Colors.grey.shade300)),
      ),
    );
  }

  // 构建系统消息
  Widget _buildSystemMessage(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2A2A2A) : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            message.content,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? const Color(0xFFB0B0B0) : Colors.grey.shade600,
            ),
          ),
        ),
      ),
    );
  }

  // 显示消息选项菜单
  void _showMessageOptions(BuildContext context) {
    print('显示消息选项菜单');
    print(
      '消息内容: ${message.content.substring(0, message.content.length > 50 ? 50 : message.content.length)}...',
    );
    print('消息角色: ${message.role}');
    print('消息ID: ${message.id}');

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder:
          (context) => Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    '消息选项',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.copy, color: Theme.of(context).colorScheme.onSurface),
                  title: Text('复制文字', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                  onTap: () {
                    Navigator.pop(context);
                    _copyText(context);
                  },
                ),

                const SizedBox(height: 16),
              ],
            ),
          ),
    );
  }

  // 复制文字
  void _copyText(BuildContext context) {
    Clipboard.setData(ClipboardData(text: message.content));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('文字已复制到剪贴板'),
        duration: Duration(seconds: 1),
      ),
    );
  }
}

class _ThinkingDot extends StatefulWidget {
  final int index;
  final Color color;

  const _ThinkingDot({required this.index, required this.color});

  @override
  State<_ThinkingDot> createState() => _ThinkingDotState();
}

class _ThinkingDotState extends State<_ThinkingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat();

    // 为每个点添加延迟，使动画不同步
    Future.delayed(Duration(milliseconds: 150 * widget.index), () {
      if (mounted) {
        _controller.repeat();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(
            0,
            sin((_controller.value * 2 * pi) + (widget.index * 1.0)) * 4,
          ),
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: widget.color,
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }
}
