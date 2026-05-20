import 'package:ai_assistant/core/models/conversation.dart';
import 'package:ai_assistant/core/providers/conversation_provider.dart';
import 'package:ai_assistant/features/chat/providers/chat_provider.dart';
import 'package:ai_assistant/features/chat/screens/chat_config_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

class ChatAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ChatAppBar({super.key});

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final conversationProvider = context.watch<ConversationProvider>();

    // 从 ConversationProvider 获取最新的 conversation 标题
    final latestConversation = conversationProvider.getConversationById(
      chatProvider.conversation.id,
    );
    String appBarTitle = latestConversation?.title ?? chatProvider.conversation.title;

    String statusText;
    Color statusColor;

    switch (chatProvider.connectionStatus) {
      case 'connected':
        statusText = '已连接';
        statusColor = Colors.green;
        break;
      case 'connecting':
        statusText = '连接中...';
        statusColor = Colors.orange;
        break;
      case 'reconnecting':
        statusText = '重连中...';
        statusColor = Colors.orange;
        break;
      case 'disconnected':
        statusText = '已断开';
        statusColor = Colors.red;
        break;
      case 'config_missing':
        statusText = '缺少服务配置';
        statusColor = Colors.blue;
        break;
      default:
        statusText = '未知状态';
        statusColor = Colors.grey;
    }

    return AppBar(
      backgroundColor: Theme.of(context).colorScheme.surface,
      elevation: 1,
      toolbarHeight: 70,
      centerTitle: true,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Theme.of(context).brightness == Brightness.dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: Theme.of(context).brightness,
      ),
      title: GestureDetector(
        onTap: () async {
          final result = await Navigator.push<dynamic>(
            context,
            MaterialPageRoute(
              builder:
                  (context) => ChatConfigScreen(
                    conversationId: chatProvider.conversation.id,
                    initialTitle: chatProvider.conversation.title,
                    conversationType: chatProvider.conversation.type,
                    configId: chatProvider.conversation.configId,
                  ),
            ),
          );
          // 如果返回的是字体大小，更新 ChatProvider
          if (result is double) {
            chatProvider.setFontSize(result);
          }
          // 从 ChatConfigScreen 返回时，重新加载字体大小
          chatProvider.reloadFontSize();
        },
        child: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Column(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    appBarTitle,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.arrow_forward_ios,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    size: 11,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    statusText,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (chatProvider.conversation.type == ConversationType.dify)
          IconButton(
            icon: Icon(Icons.refresh, color: Theme.of(context).colorScheme.onSurface, size: 24),
            tooltip: '开始新对话',
            onPressed: () => chatProvider.resetConversation(),
          ),
        if (chatProvider.conversation.type == ConversationType.diy)
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    chatProvider.isSoundPlaybackEnabled
                        ? Icons.volume_up_outlined
                        : Icons.volume_off_outlined,
                    color: Theme.of(context).colorScheme.onSurface,
                    size: 24,
                  ),
                  tooltip:
                      chatProvider.isSoundPlaybackEnabled ? '点击静音' : '点击开启声音',
                  onPressed: () {
                    chatProvider.toggleMute();
                  },
                ),
                const SizedBox(width: 4),
                IconButton(
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.phone_outlined,
                    color: Theme.of(context).colorScheme.onSurface,
                    size: 24,
                  ),
                  tooltip: '语音通话',
                  onPressed: () => chatProvider.navigateToTelephony(),
                ),
              ],
            ),
          ),
        const SizedBox(width: 8),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(70);
}
