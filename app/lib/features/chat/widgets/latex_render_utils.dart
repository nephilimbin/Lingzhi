import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:ai_assistant/core/utils/app_logger.dart';

/// LaTeX 数学公式渲染工具类
///
/// 提供数学公式的解析、提取和渲染功能
/// 支持以下格式：
/// - 行内公式：`$公式$` 或 `\(公式\)`
/// - 块级公式：`$$公式$$` 或 `\[公式\]`
class LatexRenderUtils {
  LatexRenderUtils._internal();

  /// 行内公式正则表达式：匹配 $...$ 或 \(...\)
  ///
  /// 注意：\(...\) 格式使用 [\s\S] 来匹配任意字符（包括换行和括号），
  /// 以支持包含括号的复杂公式如 \( \mathcal{L}(x, y, \lambda) \)
  static final RegExp _inlineLatexRegex = RegExp(
    r'(?<!\$)\$(?!\$)([^\$]+?)\$(?!\$)|\\\(([\s\S]+?)\\\)',
  );

  /// 块级公式正则表达式：匹配 $$...$$ 或 \[...\]
  static final RegExp _blockLatexRegex = RegExp(
    r'\$\$([\s\S]+?)\$\$|\\\[([\s\S]+?)\\\]',
  );

  /// 检查文本中是否包含 LaTeX 公式
  ///
  /// [text] 要检查的文本
  /// 返回是否包含公式
  static bool containsLatex(String text) {
    return _inlineLatexRegex.hasMatch(text) || _blockLatexRegex.hasMatch(text);
  }

  /// 提取所有公式及其位置
  ///
  /// [text] 要解析的文本
  /// 返回公式列表，每个元素包含公式文本、是否为块级、起始和结束位置
  static List<LatexMatch> extractLatex(String text) {
    final List<LatexMatch> matches = <LatexMatch>[];

    // 提取块级公式
    for (final RegExpMatch match in _blockLatexRegex.allMatches(text)) {
      // $$...$$ 格式在 group(1)，\[...\] 格式在 group(2)
      final String? formula = match.group(1) ?? match.group(2);
      if (formula != null) {
        matches.add(LatexMatch(
          formula: formula.trim(),
          isBlock: true,
          startIndex: match.start,
          endIndex: match.end,
          fullMatch: match.group(0)!,
        ));
      }
    }

    // 提取行内公式
    for (final RegExpMatch match in _inlineLatexRegex.allMatches(text)) {
      // $...$ 格式在 group(1)，\(...\) 格式在 group(2)
      final String? formula = match.group(1) ?? match.group(2);
      if (formula != null) {
        matches.add(LatexMatch(
          formula: formula.trim(),
          isBlock: false,
          startIndex: match.start,
          endIndex: match.end,
          fullMatch: match.group(0)!,
        ));
      }
    }

    // 按位置排序
    matches.sort((LatexMatch a, LatexMatch b) => a.startIndex.compareTo(b.startIndex));

    return matches;
  }

  /// 将文本分割为普通文本段和公式段
  ///
  /// [text] 要分割的文本
  /// 返回文本段列表
  static List<TextSegment> splitTextWithLatex(String text) {
    final List<TextSegment> segments = <TextSegment>[];

    // 如果不包含公式，直接返回
    if (!containsLatex(text)) {
      segments.add(TextSegment(text: text, isLatex: false));
      return segments;
    }

    // 提取所有公式匹配
    final List<LatexMatch> latexMatches = extractLatex(text);

    // 如果没有匹配到公式，返回原始文本
    if (latexMatches.isEmpty) {
      segments.add(TextSegment(text: text, isLatex: false));
      return segments;
    }

    int currentIndex = 0;

    for (final LatexMatch match in latexMatches) {
      // 添加公式前的普通文本
      if (match.startIndex > currentIndex) {
        final String normalText = text.substring(currentIndex, match.startIndex);
        if (normalText.isNotEmpty) {
          segments.add(TextSegment(text: normalText, isLatex: false));
        }
      }

      // 添加公式段
      segments.add(TextSegment(
        text: match.formula,
        isLatex: true,
        isBlock: match.isBlock,
      ));

      currentIndex = match.endIndex;
    }

    // 添加最后剩余的普通文本
    if (currentIndex < text.length) {
      final String remainingText = text.substring(currentIndex);
      if (remainingText.isNotEmpty) {
        segments.add(TextSegment(text: remainingText, isLatex: false));
      }
    }

    return segments;
  }

  /// 渲染单个 LaTeX 公式
  ///
  /// [formula] LaTeX 公式字符串
  /// [style] 文本样式
  /// [isBlock] 是否为块级公式
  static Widget renderLatex(
    String formula, {
    TextStyle? style,
    bool isBlock = false,
  }) {
    try {
      final Math mathWidget = Math.tex(
        formula,
        textStyle: style,
        mathStyle: isBlock ? MathStyle.display : MathStyle.text,
      );

      if (isBlock) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          alignment: Alignment.centerLeft,
          child: mathWidget,
        );
      }

      return mathWidget;
    } catch (e) {
      // 公式解析失败时显示原始文本
      logW('LaTeX公式解析失败: $e');
      return Text(
        formula,
        style: style?.copyWith(
          color: style.color ?? Colors.red,
          backgroundColor: Colors.red.withValues(alpha: 0.1),
        ),
      );
    }
  }

  /// 渲染包含混合内容（文本+公式）的 Widget
  ///
  /// [text] 包含公式的文本
  /// [textStyle] 普通文本样式
  /// [latexStyle] 公式样式（可选，默认使用 textStyle）
  static Widget renderMixedContent(
    String text, {
    TextStyle? textStyle,
    TextStyle? latexStyle,
  }) {
    // 如果不包含公式，直接返回普通文本
    if (!containsLatex(text)) {
      return Text(text, style: textStyle);
    }

    final List<TextSegment> segments = splitTextWithLatex(text);

    // 如果只有一个公式段
    if (segments.length == 1 && segments.first.isLatex) {
      return renderLatex(
        segments.first.text,
        style: latexStyle ?? textStyle,
        isBlock: segments.first.isBlock ?? false,
      );
    }

    // 构建行内 Widget 列表
    final List<Widget> inlineWidgets = <Widget>[];
    final List<Widget> blockWidgets = <Widget>[];

    for (final TextSegment segment in segments) {
      if (segment.isLatex) {
        final Widget latexWidget = renderLatex(
          segment.text,
          style: latexStyle ?? textStyle,
          isBlock: segment.isBlock ?? false,
        );

        if (segment.isBlock == true) {
          // 块级公式需要单独一行
          blockWidgets.add(latexWidget);
        } else {
          // 行内公式
          inlineWidgets.add(latexWidget);
        }
      } else {
        // 普通文本
        inlineWidgets.add(Text(segment.text, style: textStyle));
      }
    }

    // 如果只有行内元素，使用 Wrap
    if (blockWidgets.isEmpty) {
      return Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: inlineWidgets,
      );
    }

    // 如果有块级元素，使用 Column
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (inlineWidgets.isNotEmpty)
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: inlineWidgets,
          ),
        ...blockWidgets,
      ],
    );
  }
}

/// LaTeX 公式匹配结果
class LatexMatch {
  /// 公式内容（不含分隔符）
  final String formula;

  /// 是否为块级公式
  final bool isBlock;

  /// 匹配起始位置
  final int startIndex;

  /// 匹配结束位置
  final int endIndex;

  /// 完整匹配的文本（含分隔符）
  final String fullMatch;

  const LatexMatch({
    required this.formula,
    required this.isBlock,
    required this.startIndex,
    required this.endIndex,
    required this.fullMatch,
  });

  @override
  String toString() => 'LatexMatch(formula: $formula, isBlock: $isBlock, range: $startIndex-$endIndex)';
}

/// 文本段（可能是普通文本或公式）
class TextSegment {
  /// 文本内容
  final String text;

  /// 是否为 LaTeX 公式
  final bool isLatex;

  /// 是否为块级公式（仅当 isLatex 为 true 时有效）
  final bool? isBlock;

  const TextSegment({
    required this.text,
    required this.isLatex,
    this.isBlock,
  });

  @override
  String toString() => 'TextSegment(text: $text, isLatex: $isLatex, isBlock: $isBlock)';
}

/// Markdown 内联格式解析工具类
///
/// 支持解析以下 Markdown 内联格式：
/// - **粗体** 或 __粗体__
/// - *斜体* 或 _斜体_
/// - `代码`
/// - ~~删除线~~
class MarkdownInlineParser {
  MarkdownInlineParser._internal();

  /// 所有内联格式的组合正则
  ///
  /// 匹配顺序：粗体 -> 斜体 -> 代码 -> 删除线
  /// 注意：斜体正则使用负向后顾断言避免匹配 ** 或 __
  static final RegExp _allInlineRegex = RegExp(
    r'(\*\*|__)(?=\S)(.+?)(?<=\S)\1|' // 粗体
    r'(?<!\*|\_|\\)(\*|_)(?=\S)(.+?)(?<=\S)(?<!\*|\_|\\)\3|' // 斜体
    r'`([^`]+)`|' // 代码
    r'~~(.+?)~~', // 删除线
  );

  /// 检查文本中是否包含 Markdown 内联格式
  ///
  /// [text] 要检查的文本
  /// 返回是否包含内联格式
  static bool containsInlineMarkdown(String text) {
    return _allInlineRegex.hasMatch(text);
  }

  /// 解析文本中的 Markdown 内联格式，返回 InlineSpan 列表
  ///
  /// [text] 要解析的文本
  /// [baseStyle] 基础文本样式
  /// [codeStyle] 代码样式（可选）
  /// 返回 InlineSpan 列表，可直接用于 RichText
  static List<InlineSpan> parseInlineMarkdown(
    String text, {
    TextStyle? baseStyle,
    TextStyle? codeStyle,
  }) {
    final List<InlineSpan> spans = <InlineSpan>[];

    if (text.isEmpty) {
      return spans;
    }

    // 查找所有匹配
    final List<_MarkdownMatch> matches = <_MarkdownMatch>[];

    for (final RegExpMatch match in _allInlineRegex.allMatches(text)) {
      final String fullMatch = match.group(0)!;
      String? content;
      _MarkdownFormat format;

      // 判断匹配的是哪种格式
      if (match.group(1) != null) {
        // 粗体 **text** 或 __text__
        content = match.group(2);
        format = _MarkdownFormat.bold;
      } else if (match.group(4) != null) {
        // 斜体 *text* 或 _text_
        content = match.group(4);
        format = _MarkdownFormat.italic;
      } else if (match.group(5) != null) {
        // 代码 `text`
        content = match.group(5);
        format = _MarkdownFormat.code;
      } else if (match.group(6) != null) {
        // 删除线 ~~text~~
        content = match.group(6);
        format = _MarkdownFormat.strikethrough;
      } else {
        continue;
      }

      if (content != null && content.isNotEmpty) {
        matches.add(_MarkdownMatch(
          content: content,
          format: format,
          startIndex: match.start,
          endIndex: match.end,
          fullMatch: fullMatch,
        ));
      }
    }

    // 如果没有匹配，返回普通文本
    if (matches.isEmpty) {
      spans.add(TextSpan(text: text, style: baseStyle));
      return spans;
    }

    // 按位置排序
    matches.sort((_MarkdownMatch a, _MarkdownMatch b) => a.startIndex.compareTo(b.startIndex));

    int currentIndex = 0;

    for (final _MarkdownMatch match in matches) {
      // 添加匹配前的普通文本
      if (match.startIndex > currentIndex) {
        final String normalText = text.substring(currentIndex, match.startIndex);
        if (normalText.isNotEmpty) {
          spans.add(TextSpan(text: normalText, style: baseStyle));
        }
      }

      // 添加格式化文本
      final TextStyle formattedStyle = _getStyleForFormat(match.format, baseStyle, codeStyle);
      spans.add(TextSpan(
        text: match.content,
        style: formattedStyle,
      ));

      currentIndex = match.endIndex;
    }

    // 添加最后剩余的普通文本
    if (currentIndex < text.length) {
      final String remainingText = text.substring(currentIndex);
      if (remainingText.isNotEmpty) {
        spans.add(TextSpan(text: remainingText, style: baseStyle));
      }
    }

    return spans;
  }

  /// 根据格式类型获取对应的文本样式
  ///
  /// [format] Markdown 格式类型
  /// [baseStyle] 基础样式
  /// [codeStyle] 代码样式（可选）
  static TextStyle _getStyleForFormat(
    _MarkdownFormat format,
    TextStyle? baseStyle,
    TextStyle? codeStyle,
  ) {
    switch (format) {
      case _MarkdownFormat.bold:
        return baseStyle?.copyWith(fontWeight: FontWeight.bold) ??
            const TextStyle(fontWeight: FontWeight.bold);
      case _MarkdownFormat.italic:
        return baseStyle?.copyWith(fontStyle: FontStyle.italic) ??
            const TextStyle(fontStyle: FontStyle.italic);
      case _MarkdownFormat.code:
        if (codeStyle != null) {
          return codeStyle;
        }
        if (baseStyle != null) {
          return baseStyle.copyWith(
            fontFamily: 'monospace',
            backgroundColor: const Color(0xFFE8E8E8),
            fontSize: (baseStyle.fontSize ?? 14) * 0.9,
          );
        }
        return const TextStyle(
          fontFamily: 'monospace',
          backgroundColor: Color(0xFFE8E8E8),
          fontSize: 12.6,
        );
      case _MarkdownFormat.strikethrough:
        return baseStyle?.copyWith(decoration: TextDecoration.lineThrough) ??
            const TextStyle(decoration: TextDecoration.lineThrough);
    }
  }
}

/// Markdown 内联格式类型
enum _MarkdownFormat {
  /// 粗体
  bold,

  /// 斜体
  italic,

  /// 行内代码
  code,

  /// 删除线
  strikethrough,
}

/// Markdown 内联格式匹配结果
class _MarkdownMatch {
  /// 格式化内容（不含标记符号）
  final String content;

  /// 格式类型
  final _MarkdownFormat format;

  /// 匹配起始位置
  final int startIndex;

  /// 匹配结束位置
  final int endIndex;

  /// 完整匹配的文本（含标记符号）
  final String fullMatch;

  const _MarkdownMatch({
    required this.content,
    required this.format,
    required this.startIndex,
    required this.endIndex,
    required this.fullMatch,
  });
}
