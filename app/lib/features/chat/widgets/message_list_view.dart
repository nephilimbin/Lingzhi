import 'dart:math';
import 'package:ai_assistant/core/models/conversation.dart';
import 'package:ai_assistant/core/models/message.dart';
import 'package:ai_assistant/core/providers/conversation_provider.dart';
import 'package:ai_assistant/features/chat/providers/chat_provider.dart';
import 'package:ai_assistant/features/chat/widgets/message_bubble.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

// Helper extension for DateTime (Top-level declaration)
extension DateTimeComparison on DateTime {
  bool isAtSameDayAs(DateTime other) {
    return year == other.year && month == other.month && day == other.day;
  }
}

// Helper class to remove overscroll effect
class NoOverscrollBehavior extends ScrollBehavior {
  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}

class MessageListView extends StatelessWidget {
  const MessageListView({super.key});

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final conversationProvider = context.watch<ConversationProvider>();
    final messagesFromProvider = conversationProvider.getMessages(
      chatProvider.conversation.id,
    );

    if (messagesFromProvider.isEmpty) {
      return _buildEmptyState(context, chatProvider.conversation.type);
    }

    // 对消息进行排序，最新的消息在前面（用于reverse: true的ListView）
    List<Message> sortedMessages = List<Message>.from(messagesFromProvider);
    sortedMessages.sort((a, b) {
      return b.timestamp.compareTo(a.timestamp); // 最新的在前面
    });

    return ScrollConfiguration(
      behavior: NoOverscrollBehavior(),
      child: NotificationListener<ScrollNotification>(
        onNotification: (ScrollNotification scrollInfo) {
          // 检测用户是否手动滚动
          if (scrollInfo is ScrollStartNotification) {
            if (scrollInfo.dragDetails != null) {
              chatProvider.setUserInteractedWithScroll(true);
            }
          }

          // 检测是否滚动到顶部，触发加载更多
          if (scrollInfo is ScrollUpdateNotification) {
            if (scrollInfo.metrics.pixels >=
                    scrollInfo.metrics.maxScrollExtent - 100 &&
                !chatProvider.isLoadingMore) {
              chatProvider.loadMoreMessages();
            }
          }

          return false;
        },
        child: ListView.builder(
          controller: chatProvider.scrollController,
          reverse: true, // 反向列表，最新消息在底部
          physics:
              const ClampingScrollPhysics(), // 使用ClampingScrollPhysics避免弹性滚动
          itemCount:
              sortedMessages.length + (chatProvider.isLoadingMore ? 1 : 0),
          itemBuilder: (context, index) {
            // 加载更多指示器
            if (index == sortedMessages.length) {
              return _buildLoadingMoreIndicator();
            }

            final message = sortedMessages[index];
            final previousMessage =
                index < sortedMessages.length - 1
                    ? sortedMessages[index + 1]
                    : null;

            // 检查是否需要显示日期分隔符
            bool showDateSeparator = false;
            if (previousMessage == null ||
                !message.timestamp.isAtSameDayAs(previousMessage.timestamp)) {
              showDateSeparator = true;
            }

            return Column(
              children: [
                if (showDateSeparator) _buildDateSeparator(message.timestamp),
                MessageBubble(
                  message: message,
                  conversationType: chatProvider.conversation.type,
                ),
                // 在最新消息后显示等待气泡
                if (index == 0 && (chatProvider.isUserWaiting || chatProvider.isAssistantWaiting))
                  _buildWaitingBubble(chatProvider.isUserWaiting, chatProvider.isAssistantWaiting),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, ConversationType type) {
    String title;
    String subtitle;
    IconData icon;

    switch (type) {
      case ConversationType.diy:
        title = '开始与小助理对话';
        subtitle = '你可以通过文字或语音与小助理交流';
        icon = Icons.chat_bubble_outline;
        break;
      case ConversationType.dify:
        title = '开始新对话';
        subtitle = '输入消息开始与AI助手对话';
        icon = Icons.psychology_outlined;
        break;
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 80, color: Colors.grey.shade400),
          const SizedBox(height: 24),
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade500),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildDateSeparator(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final messageDate = DateTime(date.year, date.month, date.day);

    String dateText;
    if (messageDate == today) {
      dateText = '今天';
    } else if (messageDate == yesterday) {
      dateText = '昨天';
    } else {
      dateText = DateFormat('MM月dd日').format(date);
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            dateText,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingMoreIndicator() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  Widget _buildWaitingBubble(bool showUserWaiting, bool showAssistantWaiting) {
    return Column(
      children: [
        if (showUserWaiting)
          _buildSingleWaitingBubble(true),
        if (showAssistantWaiting)
          _buildSingleWaitingBubble(false),
      ],
    );
  }

  Widget _buildSingleWaitingBubble(bool isUser) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isUser ? Colors.blue : const Color(0xFFF0F0F0),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildPulsatingDot(0, isUser),
                _buildPulsatingDot(1, isUser),
                _buildPulsatingDot(2, isUser),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPulsatingDot(int index, bool isUser) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      child: _WaitingDot(index: index, color: isUser ? Colors.white : Colors.grey.shade600),
    );
  }
}

class _WaitingDot extends StatefulWidget {
  final int index;
  final Color color;

  const _WaitingDot({required this.index, required this.color});

  @override
  State<_WaitingDot> createState() => _WaitingDotState();
}

class _WaitingDotState extends State<_WaitingDot>
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
