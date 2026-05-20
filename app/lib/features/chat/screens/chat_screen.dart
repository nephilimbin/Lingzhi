import 'package:ai_assistant/core/models/conversation.dart';
import 'package:ai_assistant/core/providers/config_provider.dart';
import 'package:ai_assistant/core/providers/conversation_provider.dart';
import 'package:ai_assistant/core/providers/diy_service_provider.dart';
import 'package:ai_assistant/features/chat/providers/chat_provider.dart';
import 'package:ai_assistant/features/chat/widgets/chat_app_bar.dart';
import 'package:ai_assistant/features/chat/widgets/chat_input_bar.dart';
import 'package:ai_assistant/features/chat/widgets/message_list_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

class ChatScreen extends StatefulWidget {
  final Conversation conversation;

  const ChatScreen({required this.conversation, super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // 将生命周期事件传递给ChatProvider处理
    final chatProvider = context.read<ChatProvider>();
    chatProvider.handleAppLifecycleChange(state);
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create:
          (context) => ChatProvider(
            conversation: widget.conversation,
            conversationProvider: context.read<ConversationProvider>(),
            diyServiceProvider: context.read<DiyServiceProvider>(),
            configProvider: context.read<ConfigProvider>(),
            context: context,
          ),
      child: const ChatView(),
    );
  }
}

class ChatView extends StatefulWidget {
  const ChatView({super.key});

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  @override
  Widget build(BuildContext context) {
    // 确保状态栏设置正确
    final isDark = Theme.of(context).brightness == Brightness.dark;
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
    );

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      resizeToAvoidBottomInset: true, // 使用Flutter原生键盘处理
      appBar: const ChatAppBar(),
      body: GestureDetector(
        onTap: () {
          // 点击空白区域隐藏键盘
          FocusScope.of(context).unfocus();
        },
        behavior: HitTestBehavior.translucent,
        child: Stack(
          children: [
            SafeArea(
              top: false,
              bottom: false,
              child: Column(
                children: [
                  // 消息列表
                  const Expanded(
                    child: MessageListView(),
                  ),
                  // 输入栏
                  const ChatInputBar(),
                ],
              ),
            ),
            ],
        ),
      ),
    );
  }
}
