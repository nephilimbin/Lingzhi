import 'package:flutter/material.dart';
import 'package:ai_assistant/core/models/conversation.dart';
import 'package:ai_assistant/features/conversation/providers/search_provider.dart';

class SearchResultsList extends StatelessWidget {
  final SearchProvider searchProvider;

  const SearchResultsList({
    required this.searchProvider,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (!searchProvider.hasQuery) {
      return const SizedBox.shrink();
    }

    if (!searchProvider.hasResults) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.search_off,
                size: 64,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
              ),
              const SizedBox(height: 16),
              Text(
                '未找到匹配的对话',
                style: TextStyle(
                  fontSize: 18,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: searchProvider.searchResults.length,
      itemBuilder: (context, index) {
        final result = searchProvider.searchResults[index];
        final conversation = result['conversation'] as Conversation;

        return _buildSearchResultItem(context, conversation);
      },
    );
  }

  Widget _buildSearchResultItem(BuildContext context, Conversation conversation) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ListTile(
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: conversation.type == ConversationType.dify
            ? Colors.blue.shade400
            : Colors.purple.shade400,
        child: Icon(
          conversation.type == ConversationType.dify
              ? Icons.chat_bubble_outline
              : Icons.mic,
          color: Colors.white,
          size: 20,
        ),
      ),
      title: Text(
        conversation.title,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 16,
          color: theme.colorScheme.onSurface,
        ),
      ),
      subtitle: Text(
        conversation.lastMessage,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 14,
          color: isDark ? const Color(0xFFB0B0B0) : Colors.grey.shade600,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: isDark ? const Color(0xFF757575) : Colors.grey.shade400,
        size: 20,
      ),
      onTap: () => searchProvider.navigateToConversation(conversation),
    );
  }
}
