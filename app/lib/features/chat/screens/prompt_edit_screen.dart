import 'package:flutter/material.dart';

/// 提示词编辑页面
/// 用于编写和编辑长文本的提示词内容
class PromptEditScreen extends StatefulWidget {
  const PromptEditScreen({super.key});

  @override
  State<PromptEditScreen> createState() => _PromptEditScreenState();
}

class _PromptEditScreenState extends State<PromptEditScreen> {
  final TextEditingController _promptController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // TODO: 加载已保存的提示词
    _promptController.text = '';
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  void _savePrompt() {
    final prompt = _promptController.text.trim();
    // TODO: 保存提示词到本地存储或服务器
    Navigator.of(context).pop(prompt);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: _buildAppBar(),
      body: Column(
        children: [
          // 提示区域
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Text('💡', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '提示词将作为AI助手的行为指导，影响对话的回复风格和内容',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade700,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 编辑区域
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TextField(
                controller: _promptController,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(
                  fontSize: 15,
                  color: Color(0xFF111827),
                  height: 1.5,
                ),
                decoration: const InputDecoration(
                  hintText: '在此输入您的提示词...\n\n例如：\n• 你是一个友善的AI助手\n• 回复简洁明了\n• 使用表情符号增加趣味性',
                  hintStyle: TextStyle(
                    color: Color(0xFF9CA3AF),
                    fontSize: 15,
                    height: 1.5,
                  ),
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
          // 字符计数
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '字符数: ${_promptController.text.length}',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                  ),
                ),
                Text(
                  '建议 500-2000 字符',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade400,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 底部保存按钮
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _savePrompt,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  '保存提示词',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: const Text(
        '编辑提示词',
        style: TextStyle(
          color: Color(0xFF111827),
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      backgroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      iconTheme: const IconThemeData(color: Color(0xFF111827)),
      leading: IconButton(
        icon: const Icon(Icons.close, size: 24),
        onPressed: () => Navigator.of(context).pop(),
      ),
      actions: [
        TextButton(
          onPressed: _savePrompt,
          child: const Text(
            '完成',
            style: TextStyle(
              color: Color(0xFF007AFF),
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
