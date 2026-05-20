import 'package:flutter/material.dart';
import 'package:ai_assistant/core/models/conversation.dart';
import 'package:ai_assistant/core/models/message.dart';
import 'package:ai_assistant/core/providers/conversation_provider.dart';
import 'package:ai_assistant/features/chat/screens/chat_screen.dart';

class SearchProvider extends ChangeNotifier {
  final BuildContext context;
  final ConversationProvider conversationProvider;
  final TextEditingController searchController = TextEditingController();

  SearchProvider({
    required this.context,
    required this.conversationProvider,
  }) {
    searchController.addListener(_onSearchChanged);
  }

  // 状态变量
  String _query = '';
  final List<Map<String, dynamic>> _searchResults = [];

  // Getters
  String get query => _query;
  List<Map<String, dynamic>> get searchResults => _searchResults;
  bool get hasQuery => _query.isNotEmpty;
  bool get hasResults => _searchResults.isNotEmpty;

  // 搜索输入变化处理
  void _onSearchChanged() {
    final newQuery = searchController.text.trim();
    if (_query != newQuery) {
      _query = newQuery;
      _performSearch();
      notifyListeners();
    }
  }

  // 执行搜索
  void _performSearch() {
    _searchResults.clear();

    if (_query.isEmpty) {
      return;
    }

    final conversations = conversationProvider.conversations;
    
    for (final conversation in conversations) {
      final messages = conversationProvider.getMessages(conversation.id);
      final allContent = '${messages.map((m) => m.content).join(' ')} ${conversation.title}'
          .toLowerCase();
      
      if (allContent.contains(_query.toLowerCase())) {
        // 找到最近一次匹配的消息时间
        final matchMsg = messages.lastWhere(
          (m) => m.content.toLowerCase().contains(_query.toLowerCase()),
          orElse: () => messages.isNotEmpty
              ? messages.last
              : Message(
                  id: '',
                  conversationId: conversation.id,
                  role: MessageRole.user,
                  content: '',
                  timestamp: conversation.lastMessageTime,
                  isRead: true,
                  isImage: false,
                ),
        );
        final matchTime = matchMsg.timestamp;
        _searchResults.add({
          'conversation': conversation,
          'matchTime': matchTime,
        });
      }
    }
    
    // 按匹配时间排序，最新的在前
    _searchResults.sort((a, b) => b['matchTime'].compareTo(a['matchTime']));
  }

  // 清空搜索
  void clearSearch() {
    _query = '';
    searchController.clear();
    _searchResults.clear();
    notifyListeners();
  }

  // 导航到对话
  void navigateToConversation(Conversation conversation) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(conversation: conversation),
      ),
    );
  }

  // 返回上一页
  void navigateBack() {
    Navigator.pop(context);
  }

  @override
  void dispose() {
    searchController.removeListener(_onSearchChanged);
    searchController.dispose();
    super.dispose();
  }
}
