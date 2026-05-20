import 'package:flutter/material.dart';

class EmptyConversationState extends StatelessWidget {
  const EmptyConversationState({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2A2A2A) : Colors.grey.shade100,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.chat_bubble_outline,
              size: 36,
              color: isDark ? const Color(0xFF757575) : Colors.grey.shade400,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '没有对话',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.normal,
              color: isDark ? const Color(0xFF757575) : Colors.grey.shade400,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2A2A2A) : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.add_circle_outline,
                  size: 16,
                  color: isDark ? const Color(0xFF757575) : Colors.grey.shade500,
                ),
                const SizedBox(width: 6),
                Text(
                  '点击 + 创建新对话',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? const Color(0xFF757575) : Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
