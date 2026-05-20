import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ai_assistant/core/providers/conversation_provider.dart';
import 'package:ai_assistant/features/conversation/providers/search_provider.dart';
import 'package:ai_assistant/features/conversation/widgets/search_app_bar.dart';
import 'package:ai_assistant/features/conversation/widgets/search_results_list.dart';

class SearchConversationScreen extends StatefulWidget {
  const SearchConversationScreen({super.key});

  @override
  State<SearchConversationScreen> createState() =>
      _SearchConversationScreenState();
}

class _SearchConversationScreenState extends State<SearchConversationScreen> {
  late SearchProvider _searchProvider;

  @override
  void initState() {
    super.initState();
    final conversationProvider = Provider.of<ConversationProvider>(context, listen: false);
    _searchProvider = SearchProvider(
      context: context,
      conversationProvider: conversationProvider,
    );
  }

  @override
  void dispose() {
    _searchProvider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ChangeNotifierProvider.value(
      value: _searchProvider,
      child: Consumer<SearchProvider>(
        builder: (context, searchProvider, child) {
          return Scaffold(
            backgroundColor: theme.colorScheme.surface,
            appBar: SearchAppBar(searchProvider: searchProvider),
            body: SearchResultsList(searchProvider: searchProvider),
          );
        },
      ),
    );
  }
}
