import 'package:flutter/material.dart';
import 'package:ai_assistant/features/conversation/providers/home_provider.dart';

class HomeAppBar extends StatelessWidget implements PreferredSizeWidget {
  final HomeProvider homeProvider;

  const HomeAppBar({required this.homeProvider, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return AppBar(
      title: Text(
        '对话',
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.onSurface,
        ),
      ),
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: theme.colorScheme.surface,
      centerTitle: true,
      titleSpacing: 0,
      toolbarHeight: 64,
      leading: Center(
        child: IconButton(
          icon: Transform.translate(
            offset: const Offset(0, 1),
            child: Icon(Icons.search, size: 26, color: theme.colorScheme.onSurface),
          ),
          onPressed: () {
            homeProvider.navigateToSearch();
          },
        ),
      ),
      actions: [
        IconButton(
          icon: Icon(Icons.add, size: 26, color: theme.colorScheme.onSurface),
          onPressed: () {
            homeProvider.navigateToNewConversation();
          },
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          height: 1,
          color: isDark ? const Color(0xFF3A3A3A) : const Color(0xFFE5E7EB),
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(64);
}
