import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

import 'package:ai_assistant/features/chat/widgets/code_block_builder.dart';
import 'package:ai_assistant/features/chat/widgets/latex_render_utils.dart';
import 'package:ai_assistant/core/utils/app_logger.dart';

/// 混合内容渲染组件
///
/// 支持同时渲染 Markdown 和 LaTeX 数学公式
/// 公式格式：
/// - 行内公式：`$公式$` 或 `\(公式\)`
/// - 块级公式：`$$公式$$` 或 `\[公式\]`
///
/// 渲染策略：
/// 1. 不包含公式的内容：直接使用 MarkdownBody 渲染
/// 2. 包含块级公式：按块分割，独立渲染
/// 3. 包含行内公式的段落：
///    - 非列表内容：使用 Wrap 布局
///    - 列表内容：逐项处理，保持行内布局
class MixedContentWidget extends StatelessWidget {
  /// 要渲染的内容
  final String content;

  /// Markdown 样式表
  final MarkdownStyleSheet? styleSheet;

  /// 是否可选择
  final bool selectable;

  /// 链接点击回调
  final void Function(String text, String? href, String? title)? onTapLink;

  /// Markdown 扩展集
  final md.ExtensionSet? extensionSet;

  /// 自定义构建器
  final Map<String, MarkdownElementBuilder>? builders;

  const MixedContentWidget({
    required this.content,
    super.key,
    this.styleSheet,
    this.selectable = true,
    this.onTapLink,
    this.extensionSet,
    this.builders,
  });

  @override
  Widget build(BuildContext context) {
    // 如果内容不包含公式，直接使用 MarkdownBody
    if (!LatexRenderUtils.containsLatex(content)) {
      return _buildMarkdownBody(context, content);
    }

    // 对于包含公式的内容，使用分段处理
    return _MixedContentRenderer(
      content: content,
      styleSheet: styleSheet,
      selectable: selectable,
      onTapLink: onTapLink ?? _defaultOnTapLink,
      extensionSet: extensionSet ?? md.ExtensionSet.gitHubFlavored,
      builders: _mergedBuilders(context),
    );
  }

  /// 合并自定义构建器
  Map<String, MarkdownElementBuilder> _mergedBuilders(BuildContext context) {
    return <String, MarkdownElementBuilder>{
      'code': CustomCodeBlockBuilder(context: context),
      ...?builders,
    };
  }

  /// 构建 MarkdownBody
  Widget _buildMarkdownBody(BuildContext context, String data) {
    return MarkdownBody(
      data: data,
      selectable: selectable,
      styleSheet: styleSheet,
      onTapLink: onTapLink ?? _defaultOnTapLink,
      extensionSet: extensionSet ?? md.ExtensionSet.gitHubFlavored,
      builders: _mergedBuilders(context),
      listItemCrossAxisAlignment: MarkdownListItemCrossAxisAlignment.start,
    );
  }

  /// 默认链接点击处理
  void _defaultOnTapLink(String text, String? href, String? title) {
    if (href == null) {
      return;
    }
    final Uri? uri = Uri.tryParse(href);
    if (uri != null) {
      try {
        launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (e) {
        logW('打开链接失败: $e');
      }
    }
  }
}

/// 混合内容渲染器（私有组件）
class _MixedContentRenderer extends StatelessWidget {
  final String content;
  final MarkdownStyleSheet? styleSheet;
  final bool selectable;
  final void Function(String text, String? href, String? title)? onTapLink;
  final md.ExtensionSet extensionSet;
  final Map<String, MarkdownElementBuilder> builders;

  const _MixedContentRenderer({
    required this.content,
    required this.selectable,
    required this.extensionSet,
    required this.builders,
    this.styleSheet,
    this.onTapLink,
  });

  @override
  Widget build(BuildContext context) {
    // 将内容按块级公式分割
    final List<ContentBlock> blocks = _parseContentBlocks(content);

    if (blocks.length == 1 && !blocks.first.hasLatex) {
      // 只有一个普通 Markdown 块
      return _buildMarkdownWidget(blocks.first.content);
    }

    // 多个块，使用 Column 组合
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: blocks.map((ContentBlock block) => _buildBlock(block, context)).toList(),
    );
  }

  /// 构建单个内容块
  Widget _buildBlock(ContentBlock block, BuildContext context) {
    if (block.isLatexBlock) {
      // 纯公式块
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: LatexRenderUtils.renderLatex(
          block.content,
          style: styleSheet?.p,
          isBlock: true,
        ),
      );
    }

    if (block.hasInlineLatex) {
      // 包含行内公式的文本
      return _buildInlineMixedContent(block.content);
    }

    // 普通 Markdown 内容
    return _buildMarkdownWidget(block.content);
  }

  /// 构建包含行内公式的混合内容
  Widget _buildInlineMixedContent(String text) {
    // 检查是否包含 Markdown 列表结构
    final bool hasListStructure = _hasMarkdownListStructure(text);

    if (!hasListStructure) {
      // 如果没有列表结构，使用简单的 Wrap 方案
      return _buildSimpleInlineContent(text);
    }

    // 对于包含列表结构的内容，使用列表处理器
    return _buildListContentWithLatex(text);
  }

  /// 检查文本是否包含 Markdown 列表结构
  bool _hasMarkdownListStructure(String text) {
    // 检测有序列表或无序列表
    final RegExp listPattern = RegExp(r'^(\s*)([-*+]|\d+\.)\s', multiLine: true);
    return listPattern.hasMatch(text);
  }

  /// 构建简单的行内混合内容（无列表结构）
  ///
  /// 使用 RichText + WidgetSpan 保持行内布局，避免 MarkdownBody 产生块级元素
  /// 支持 Markdown 内联格式（粗体、斜体、代码、删除线）
  Widget _buildSimpleInlineContent(String text) {
    final List<TextSegment> segments = LatexRenderUtils.splitTextWithLatex(text);

    // 如果只有一个公式段
    if (segments.length == 1 && segments.first.isLatex) {
      return LatexRenderUtils.renderLatex(
        segments.first.text,
        style: styleSheet?.p,
        isBlock: segments.first.isBlock ?? false,
      );
    }

    // 使用 RichText + WidgetSpan 保持行内布局
    final List<InlineSpan> spans = <InlineSpan>[];

    for (final TextSegment segment in segments) {
      if (segment.isLatex) {
        // 公式使用 WidgetSpan，保持行内对齐
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: LatexRenderUtils.renderLatex(
            segment.text,
            style: styleSheet?.p,
            isBlock: false,
          ),
        ));
      } else {
        // 普通文本：解析 Markdown 内联格式
        final List<InlineSpan> markdownSpans = MarkdownInlineParser.parseInlineMarkdown(
          segment.text,
          baseStyle: styleSheet?.p,
          codeStyle: styleSheet?.code,
        );
        spans.addAll(markdownSpans);
      }
    }

    return RichText(
      text: TextSpan(
        style: styleSheet?.p,
        children: spans,
      ),
      softWrap: true,
      overflow: TextOverflow.clip,
    );
  }

  /// 构建包含公式的列表内容
  ///
  /// 策略：
  /// 1. 解析整个文本，识别列表项和非列表内容
  /// 2. 将连续的列表项组合成列表块
  /// 3. 对每个列表项独立处理公式
  Widget _buildListContentWithLatex(String text) {
    final List<_ParsedLine> parsedLines = _parseLines(text);
    final List<Widget> widgets = <Widget>[];

    // 用于累积连续的非列表内容
    final StringBuffer nonListContent = StringBuffer();

    for (int i = 0; i < parsedLines.length; i++) {
      final _ParsedLine line = parsedLines[i];

      if (line.isListItem) {
        // 先处理之前累积的非列表内容
        if (nonListContent.isNotEmpty) {
          widgets.add(_buildNonListContent(nonListContent.toString().trimRight()));
          nonListContent.clear();
        }

        // 构建列表项
        widgets.add(_buildListItem(line.indent, line.marker, line.content));
      } else {
        // 累积非列表内容
        if (nonListContent.isNotEmpty) {
          nonListContent.write('\n');
        }
        nonListContent.write(line.originalLine);
      }
    }

    // 处理最后剩余的非列表内容
    if (nonListContent.isNotEmpty) {
      widgets.add(_buildNonListContent(nonListContent.toString().trimRight()));
    }

    if (widgets.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: widgets,
    );
  }

  /// 解析文本行
  ///
  /// 将多行内容解析为列表项和非列表内容。
  /// 支持列表项的连续内容：以空格/制表符开头但没有列表标记的行，
  /// 会被合并到前一个列表项的内容中。
  List<_ParsedLine> _parseLines(String text) {
    final List<String> lines = text.split('\n');
    final List<_ParsedLine> result = <_ParsedLine>[];

    /// 列表项正则：匹配可选缩进 + 列表标记 + 内容
    final RegExp listPattern = RegExp(r'^(\s*)([-*+]|\d+\.)\s(.*)$');

    /// 用于追踪当前正在构建的列表项
    _ParsedLine? currentListItem;

    for (int i = 0; i < lines.length; i++) {
      final String line = lines[i];
      final RegExpMatch? match = listPattern.firstMatch(line);

      if (match != null) {
        // 这是一个新的列表项
        // 先将之前累积的列表项添加到结果中
        if (currentListItem != null) {
          result.add(currentListItem);
        }

        // 创建新的列表项
        currentListItem = _ParsedLine(
          originalLine: line,
          isListItem: true,
          indent: match.group(1) ?? '',
          marker: match.group(2) ?? '',
          content: match.group(3) ?? '',
        );
      } else if (_isContinuationLine(line) && currentListItem != null) {
        // 这是一个续行（以空格/制表符开头，但不是新的列表项）
        // 将其合并到当前列表项中
        final String continuationContent = line.trim();
        if (continuationContent.isNotEmpty) {
          currentListItem = _ParsedLine(
            originalLine: '${currentListItem.originalLine}\n$line',
            isListItem: true,
            indent: currentListItem.indent,
            marker: currentListItem.marker,
            // 使用换行符连接原内容和续行内容
            content: '${currentListItem.content}\n$continuationContent',
          );
        }
      } else {
        // 非列表行，且不是续行
        // 先将之前累积的列表项添加到结果中
        if (currentListItem != null) {
          result.add(currentListItem);
          currentListItem = null;
        }

        // 添加非列表行
        result.add(_ParsedLine(
          originalLine: line,
          isListItem: false,
        ));
      }
    }

    // 处理最后一个累积的列表项
    if (currentListItem != null) {
      result.add(currentListItem);
    }

    return result;
  }

  /// 构建非列表内容
  ///
  /// 检查内容是否包含公式，如果包含则使用公式渲染逻辑
  Widget _buildNonListContent(String text) {
    if (text.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    // 检查是否包含公式
    if (LatexRenderUtils.containsLatex(text)) {
      return _buildSimpleInlineContent(text);
    }

    // 无公式，使用普通 Markdown 渲染
    return _buildMarkdownWidget(text);
  }

  /// 检查是否为列表项的续行
  ///
  /// 续行特征：
  /// 1. 以空格或制表符开头
  /// 2. 不以列表标记开头
  /// 3. 非空行
  bool _isContinuationLine(String line) {
    // 空行不算续行
    if (line.trim().isEmpty) {
      return false;
    }

    // 必须以空格或制表符开头
    if (!line.startsWith(' ') && !line.startsWith('\t')) {
      return false;
    }

    // 不能是新的列表项
    final RegExp listPattern = RegExp(r'^\s+([-*+]|\d+\.)\s');
    return !listPattern.hasMatch(line);
  }

  /// 构建包含公式的列表项
  ///
  /// 支持单行和多行内容的渲染，多行内容使用 Column 布局
  Widget _buildListItem(String indent, String marker, String content) {
    // 计算缩进（每级缩进）
    final double indentWidth = indent.length * 4.0;
    final double markerWidth = _getMarkerWidth(marker);

    // 检查是否为多行内容
    final bool isMultiline = content.contains('\n');

    // 检查内容是否包含公式
    final bool hasLatex = LatexRenderUtils.containsLatex(content);

    if (!hasLatex) {
      // 无公式，直接使用 MarkdownBody 渲染
      return Padding(
        padding: EdgeInsets.only(left: indentWidth),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              width: markerWidth,
              child: Text(
                '$marker ',
                style: styleSheet?.listBullet ?? styleSheet?.p,
                textAlign: TextAlign.right,
              ),
            ),
            Flexible(
              child: MarkdownBody(
                data: content,
                selectable: selectable,
                styleSheet: styleSheet,
                onTapLink: onTapLink,
                extensionSet: extensionSet,
                builders: builders,
              ),
            ),
          ],
        ),
      );
    }

    // 包含公式的多行内容处理
    if (isMultiline) {
      return _buildMultilineListItemWithLatex(indentWidth, markerWidth, marker, content);
    }

    // 包含公式的单行内容，使用 RichText + WidgetSpan 构建行内内容
    return _buildSingleLineListItemWithLatex(indentWidth, markerWidth, marker, content);
  }

  /// 构建单行列表项（包含公式）
  Widget _buildSingleLineListItemWithLatex(
    double indentWidth,
    double markerWidth,
    String marker,
    String content,
  ) {
    final List<TextSegment> segments = LatexRenderUtils.splitTextWithLatex(content);
    final List<InlineSpan> spans = <InlineSpan>[];

    for (final TextSegment segment in segments) {
      if (segment.isLatex) {
        // 公式使用 WidgetSpan，保持行内对齐
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: LatexRenderUtils.renderLatex(
            segment.text,
            style: styleSheet?.p,
            isBlock: false,
          ),
        ));
      } else {
        // 普通文本：解析 Markdown 内联格式
        final List<InlineSpan> markdownSpans = MarkdownInlineParser.parseInlineMarkdown(
          segment.text,
          baseStyle: styleSheet?.p,
          codeStyle: styleSheet?.code,
        );
        spans.addAll(markdownSpans);
      }
    }

    return Padding(
      padding: EdgeInsets.only(left: indentWidth),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            width: markerWidth,
            child: Text(
              '$marker ',
              style: styleSheet?.listBullet ?? styleSheet?.p,
              textAlign: TextAlign.right,
            ),
          ),
          Flexible(
            child: RichText(
              text: TextSpan(
                style: styleSheet?.p,
                children: spans,
              ),
              softWrap: true,
              overflow: TextOverflow.clip,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建多行列表项（包含公式）
  ///
  /// 使用 Column 布局处理多行内容，每行独立处理公式
  Widget _buildMultilineListItemWithLatex(
    double indentWidth,
    double markerWidth,
    String marker,
    String content,
  ) {
    final List<String> lines = content.split('\n');
    final List<Widget> lineWidgets = <Widget>[];

    for (int i = 0; i < lines.length; i++) {
      final String line = lines[i];
      final bool isFirstLine = i == 0;

      if (line.trim().isEmpty) {
        // 跳过空行
        continue;
      }

      // 检查当前行是否包含公式
      if (!LatexRenderUtils.containsLatex(line)) {
        // 无公式，使用普通文本
        if (isFirstLine) {
          // 第一行显示列表标记
          lineWidgets.add(
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SizedBox(
                  width: markerWidth,
                  child: Text(
                    '$marker ',
                    style: styleSheet?.listBullet ?? styleSheet?.p,
                    textAlign: TextAlign.right,
                  ),
                ),
                Flexible(
                  child: Text(
                    line,
                    style: styleSheet?.p,
                  ),
                ),
              ],
            ),
          );
        } else {
          // 续行，带额外缩进对齐
          lineWidgets.add(
            Padding(
              padding: EdgeInsets.only(left: markerWidth + 4),
              child: Text(
                line,
                style: styleSheet?.p,
              ),
            ),
          );
        }
      } else {
        // 包含公式，需要逐段处理
        final List<TextSegment> segments = LatexRenderUtils.splitTextWithLatex(line);
        final List<Widget> segmentWidgets = <Widget>[];

        for (final TextSegment segment in segments) {
          if (segment.isLatex) {
            segmentWidgets.add(
              LatexRenderUtils.renderLatex(
                segment.text,
                style: styleSheet?.p,
                isBlock: false,
              ),
            );
          } else if (segment.text.isNotEmpty) {
            segmentWidgets.add(
              Text(
                segment.text,
                style: styleSheet?.p,
              ),
            );
          }
        }

        if (isFirstLine) {
          // 第一行显示列表标记
          lineWidgets.add(
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SizedBox(
                  width: markerWidth,
                  child: Text(
                    '$marker ',
                    style: styleSheet?.listBullet ?? styleSheet?.p,
                    textAlign: TextAlign.right,
                  ),
                ),
                Flexible(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: segmentWidgets,
                  ),
                ),
              ],
            ),
          );
        } else {
          // 续行，带额外缩进对齐
          lineWidgets.add(
            Padding(
              padding: EdgeInsets.only(left: markerWidth + 4),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: segmentWidgets,
              ),
            ),
          );
        }
      }
    }

    // 如果没有有效的行，返回空 Widget
    if (lineWidgets.isEmpty) {
      return const SizedBox.shrink();
    }

    // 如果只有一行，直接返回
    if (lineWidgets.length == 1) {
      return Padding(
        padding: EdgeInsets.only(left: indentWidth),
        child: lineWidgets.first,
      );
    }

    // 多行使用 Column 布局
    return Padding(
      padding: EdgeInsets.only(left: indentWidth),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: lineWidgets,
      ),
    );
  }

  /// 获取列表标记的宽度
  ///
  /// 根据标记内容动态计算宽度，确保多行内容正确对齐
  double _getMarkerWidth(String marker) {
    // 基础样式
    final TextStyle baseStyle = styleSheet?.listBullet ?? styleSheet?.p ?? const TextStyle();
    final TextStyle effectiveStyle = baseStyle.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    // 使用 TextPainter 计算实际宽度
    final TextPainter painter = TextPainter(
      text: TextSpan(text: '$marker ', style: effectiveStyle),
      textDirection: TextDirection.ltr,
    )..layout();

    // 获取实际宽度，并添加一些padding
    final double actualWidth = painter.width + 4.0;
    painter.dispose();

    // 设置最小宽度，确保单字符标记有足够空间
    const double minWidth = 20.0;
    return actualWidth > minWidth ? actualWidth : minWidth;
  }

  /// 构建 Markdown Widget
  Widget _buildMarkdownWidget(String text) {
    if (text.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return MarkdownBody(
      data: text,
      selectable: selectable,
      styleSheet: styleSheet,
      onTapLink: onTapLink,
      extensionSet: extensionSet,
      builders: builders,
      listItemCrossAxisAlignment: MarkdownListItemCrossAxisAlignment.start,
    );
  }

  /// 解析内容块
  ///
  /// 将内容分割为独立的块，每个块可能是：
  /// - 纯 Markdown 内容
  /// - 块级公式
  /// - 混合内容（包含行内公式）
  static List<ContentBlock> _parseContentBlocks(String content) {
    final List<ContentBlock> blocks = <ContentBlock>[];

    // 块级公式正则
    final RegExp blockLatexRegex = RegExp(
      r'\$\$([\s\S]+?)\$\$|\\\[([\s\S]+?)\\\]',
    );

    int currentIndex = 0;
    final List<RegExpMatch> blockMatches = blockLatexRegex.allMatches(content).toList();

    for (final RegExpMatch match in blockMatches) {
      // 添加公式前的普通内容
      if (match.start > currentIndex) {
        final String normalContent = content.substring(currentIndex, match.start).trim();
        if (normalContent.isNotEmpty) {
          blocks.add(ContentBlock(
            content: normalContent,
            isLatexBlock: false,
            hasInlineLatex: LatexRenderUtils.containsLatex(normalContent) &&
                !_containsBlockLatex(normalContent),
          ));
        }
      }

      // 添加公式块
      final String? formula = match.group(1) ?? match.group(2);
      if (formula != null) {
        blocks.add(ContentBlock(
          content: formula.trim(),
          isLatexBlock: true,
          hasInlineLatex: false,
        ));
      }

      currentIndex = match.end;
    }

    // 添加最后剩余的内容
    if (currentIndex < content.length) {
      final String remainingContent = content.substring(currentIndex).trim();
      if (remainingContent.isNotEmpty) {
        blocks.add(ContentBlock(
          content: remainingContent,
          isLatexBlock: false,
          hasInlineLatex: LatexRenderUtils.containsLatex(remainingContent) &&
              !_containsBlockLatex(remainingContent),
        ));
      }
    }

    // 如果没有匹配到任何块级公式，返回整个内容作为一个块
    if (blocks.isEmpty && content.trim().isNotEmpty) {
      blocks.add(ContentBlock(
        content: content,
        isLatexBlock: false,
        hasInlineLatex: LatexRenderUtils.containsLatex(content),
      ));
    }

    return blocks;
  }

  /// 检查是否包含块级公式
  static bool _containsBlockLatex(String text) {
    final RegExp blockLatexRegex = RegExp(r'\$\$[\s\S]+?\$\$|\\\[[\s\S]+?\\\]');
    return blockLatexRegex.hasMatch(text);
  }
}

/// 解析后的行数据
class _ParsedLine {
  /// 原始行文本
  final String originalLine;

  /// 是否为列表项
  final bool isListItem;

  /// 缩进（仅列表项有效）
  final String indent;

  /// 列表标记（仅列表项有效）
  final String marker;

  /// 列表内容（仅列表项有效）
  final String content;

  const _ParsedLine({
    required this.originalLine,
    required this.isListItem,
    this.indent = '',
    this.marker = '',
    this.content = '',
  });
}

/// 内容块
class ContentBlock {
  /// 块内容
  final String content;

  /// 是否为纯公式块
  final bool isLatexBlock;

  /// 是否包含行内公式
  final bool hasInlineLatex;

  /// 是否包含任何 LaTeX
  bool get hasLatex => isLatexBlock || hasInlineLatex;

  const ContentBlock({
    required this.content,
    required this.isLatexBlock,
    required this.hasInlineLatex,
  });

  @override
  String toString() => 'ContentBlock(isLatexBlock: $isLatexBlock, hasInlineLatex: $hasInlineLatex)';
}
