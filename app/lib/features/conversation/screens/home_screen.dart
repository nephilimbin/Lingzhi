import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ai_assistant/core/providers/conversation_provider.dart';
import 'package:ai_assistant/features/conversation/providers/home_provider.dart';
import 'package:ai_assistant/features/conversation/widgets/home_app_bar.dart';
import 'package:ai_assistant/features/conversation/widgets/conversation_list_view.dart';
import 'package:ai_assistant/features/conversation/widgets/empty_conversation_state.dart';
import 'package:ai_assistant/features/conversation/widgets/bottom_navigation_bar.dart';
import 'package:ai_assistant/features/settings/screens/settings_screen.dart';
import 'package:ai_assistant/core/widgets/slidable_delete_tile.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late HomeProvider _homeProvider;

  @override
  void initState() {
    super.initState();
    final conversationProvider = Provider.of<ConversationProvider>(
      context,
      listen: false,
    );
    _homeProvider = HomeProvider(
      context: context,
      conversationProvider: conversationProvider,
    );
  }

  @override
  void dispose() {
    _homeProvider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _homeProvider,
      child: Consumer<HomeProvider>(
        builder: (context, homeProvider, child) {
          return GestureDetector(
            onTap: () {
              // 点击页面任何地方时，让搜索框失去焦点
              homeProvider.unfocusSearch();
              // 同时关闭所有打开的删除按钮
              SlidableController.instance.closeCurrentTile();
            },
            child: Scaffold(
              extendBody: true,
              extendBodyBehindAppBar: true,
              backgroundColor: Theme.of(context).colorScheme.surface,
              appBar:
                  homeProvider.selectedIndex == 0
                      ? HomeAppBar(homeProvider: homeProvider)
                      : null,
              body:
                  homeProvider.selectedIndex == 1
                      ? const SafeArea(bottom: false, child: SettingsScreen())
                      : SafeArea(
                        bottom: false,
                        child: Column(
                          children: [
                            Expanded(child: _buildConversationContent()),
                          ],
                        ),
                      ),
              floatingActionButton: null,
              bottomNavigationBar: CustomBottomNavigationBar(
                homeProvider: homeProvider,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildConversationContent() {
    return Consumer<ConversationProvider>(
      builder: (context, conversationProvider, child) {
        if (!_homeProvider.hasConversations) {
          return const EmptyConversationState();
        }
        return ConversationListView(homeProvider: _homeProvider);
      },
    );
  }
}
