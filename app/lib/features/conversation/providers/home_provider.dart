import 'package:flutter/material.dart';
import 'package:ai_assistant/core/providers/conversation_provider.dart';
import 'package:ai_assistant/core/models/conversation.dart';
import 'package:ai_assistant/features/chat/screens/chat_screen.dart';
import 'package:ai_assistant/features/conversation/screens/conversation_type_screen.dart';
import 'package:ai_assistant/features/conversation/screens/search_conversation_screen.dart';

class HomeProvider extends ChangeNotifier {
  final BuildContext context;
  final ConversationProvider conversationProvider;

  int _selectedIndex = 0;
  final FocusNode searchFocusNode = FocusNode();

  HomeProvider({required this.context, required this.conversationProvider});

  int get selectedIndex => _selectedIndex;

  List<Conversation> get pinnedConversations =>
      conversationProvider.pinnedConversations;
  List<Conversation> get unpinnedConversations =>
      conversationProvider.unpinnedConversations;

  bool get hasConversations =>
      pinnedConversations.isNotEmpty || unpinnedConversations.isNotEmpty;

  @override
  void dispose() {
    searchFocusNode.dispose();
    super.dispose();
  }

  void setSelectedIndex(int index) {
    if (_selectedIndex != index) {
      _selectedIndex = index;
      notifyListeners();
    }
  }

  void navigateToSearch() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SearchConversationScreen()),
    );
  }

  void navigateToNewConversation() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ConversationTypeScreen()),
    );
  }

  void navigateToChat(Conversation conversation) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(conversation: conversation),
      ),
    );
  }

  void deleteConversation(Conversation conversation) {
    conversationProvider.deleteConversation(conversation.id);

    // 显示撤销消息
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Expanded(
              child: Text('${conversation.title} 已删除'),
            ),
            GestureDetector(
              onTap: () {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Icon(
                  Icons.close,
                  color: Colors.white70,
                  size: 20,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.grey.shade800,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5), // 增加时长给用户更多时间操作
        margin: const EdgeInsets.only(bottom: 20, left: 20, right: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        action: SnackBarAction(
          label: '撤销',
          textColor: Colors.white,
          onPressed: () {
            conversationProvider.restoreLastDeletedConversation();
          },
        ),
      ),
    );
  }

  void togglePinConversation(Conversation conversation) {
    conversationProvider.togglePinConversation(conversation.id);
  }

  void showConversationOptions(Conversation conversation) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      elevation: 20,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 5,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 1,
                      spreadRadius: 0,
                      offset: const Offset(0, 0.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 10,
                        spreadRadius: 0,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 4,
                      ),
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 4,
                              spreadRadius: 0,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Icon(
                          conversation.isPinned
                              ? Icons.push_pin
                              : Icons.push_pin_outlined,
                          color: Colors.black,
                          size: 24,
                        ),
                      ),
                      title: Text(
                        conversation.isPinned ? '取消置顶' : '置顶对话',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        togglePinConversation(conversation);
                      },
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 10,
                        spreadRadius: 0,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 4,
                      ),
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.red.withValues(alpha: 0.1),
                              blurRadius: 4,
                              spreadRadius: 0,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.delete,
                          color: Colors.red,
                          size: 24,
                        ),
                      ),
                      title: const Text(
                        '删除对话',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.red,
                        ),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        deleteConversation(conversation);
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  void showDevelopingFeatureSnackbar() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('功能开发中...'),
        duration: Duration(milliseconds: 500),
      ),
    );
  }

  void unfocusSearch() {
    searchFocusNode.unfocus();
  }

  bool isFirstPinnedConversation(Conversation conversation) {
    return pinnedConversations.isNotEmpty &&
        pinnedConversations.first == conversation;
  }

  bool isFirstUnpinnedConversation(Conversation conversation) {
    return unpinnedConversations.isNotEmpty &&
        unpinnedConversations.first == conversation &&
        pinnedConversations.isEmpty;
  }
}
