import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:flutter_markdown/flutter_markdown.dart';

// 自定义代码块构建器
class CustomCodeBlockBuilder extends MarkdownElementBuilder {
  final BuildContext context;

  CustomCodeBlockBuilder({required this.context});

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    if (element.textContent.isEmpty) {
      return null;
    }

    final String code = element.textContent;
    String language = 'plaintext';
    if (element.attributes['class']?.startsWith('language-') == true) {
      language = element.attributes['class']!.substring('language-'.length);
    }

    return _buildCodeBlock(code, language);
  }

  Widget _buildCodeBlock(String code, String language) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 代码块头部
          _buildCodeHeader(context, code, language),
          // 代码内容
          _buildCodeContent(code, language),
        ],
      ),
    );
  }

  Widget _buildCodeHeader(BuildContext context, String code, String language) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF2D2D2D), // 深灰色背景
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(8),
          topRight: Radius.circular(8),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 语言标签
          Text(
            language.toUpperCase(),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontFamily: 'Courier',
            ),
          ),
          // 复制按钮
          GestureDetector(
            onTap: () => _copyCode(context, code),
            child: const MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Icon(
                Icons.content_copy,
                color: Colors.white70,
                size: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCodeContent(String code, String language) {
    return HighlightView(
      code,
      language: _mapLanguage(language),
      theme: atomOneDarkTheme,
      padding: const EdgeInsets.all(16),
      textStyle: const TextStyle(
        fontSize: 14,
        fontFamily: 'Courier',
        height: 1.3,
      ),
    );
  }

  void _copyCode(BuildContext context, String code) {
    Clipboard.setData(ClipboardData(text: code));
    if (!context.mounted) {
      return; // Check if the widget is still in the tree
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('代码已复制到剪贴板'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  // 映射语言名称到 flutter_highlight 支持的格式
  String _mapLanguage(String lang) {
    switch (lang.toLowerCase()) {
      case 'js':
      case 'javascript':
        return 'javascript';
      case 'ts':
      case 'typescript':
        return 'typescript';
      case 'py':
      case 'python':
        return 'python';
      case 'java':
        return 'java';
      case 'cpp':
      case 'c++':
        return 'cpp';
      case 'c':
        return 'c';
      case 'html':
        return 'xml';
      case 'css':
        return 'css';
      case 'json':
        return 'json';
      case 'yaml':
      case 'yml':
        return 'yaml';
      case 'bash':
      case 'shell':
      case 'sh':
        return 'bash';
      case 'sql':
        return 'sql';
      case 'dart':
        return 'dart';
      default:
        return 'plaintext';
    }
  }
}
