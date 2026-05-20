import 'package:flutter/material.dart';
import 'package:ai_assistant/core/models/conversation.dart';
import 'package:ai_assistant/features/conversation/providers/home_provider.dart';
import 'package:ai_assistant/features/conversation/widgets/conversation_tile.dart';
import 'package:ai_assistant/core/widgets/slidable_delete_tile.dart';

class ConversationListView extends StatelessWidget {
  final HomeProvider homeProvider;

  const ConversationListView({
    required this.homeProvider,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return ListView(
      padding: EdgeInsets.only(
        top: 4.0,
        bottom: 16 + MediaQuery.of(context).padding.bottom,
      ),
      children: [
        ...homeProvider.pinnedConversations.map(
          (conversation) => _buildConversationTile(conversation, context, isDark),
        ),
        ...homeProvider.unpinnedConversations.map(
          (conversation) => _buildConversationTile(conversation, context, isDark),
        ),
      ],
    );
  }

  Widget _buildConversationTile(Conversation conversation, BuildContext context, bool isDark) {
    final bool isFirstPinned = homeProvider.isFirstPinnedConversation(conversation);
    final bool isFirstUnpinned = homeProvider.isFirstUnpinnedConversation(conversation);

    return SlidableDeleteTile(
      key: Key(conversation.id),
      backgroundColor: (isFirstPinned || isFirstUnpinned)
          ? (isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF0F0F0))
          : (isDark ? const Color(0xFF121212) : Colors.white),
      onDelete: () {
        homeProvider.deleteConversation(conversation);
      },
      onTap: () {
        homeProvider.navigateToChat(conversation);
      },
      onLongPress: () {
        homeProvider.showConversationOptions(conversation);
      },
      child: ConversationTile(
        conversation: conversation,
        isFirstItem: isFirstPinned || isFirstUnpinned,
        onTap: null,
        onLongPress: null,
      ),
    );
  }
}
