import 'package:flutter/material.dart';
import 'package:ai_assistant/features/conversation/providers/search_provider.dart';

class SearchAppBar extends StatelessWidget implements PreferredSizeWidget {
  final SearchProvider searchProvider;

  const SearchAppBar({
    required this.searchProvider,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AppBar(
      backgroundColor: theme.colorScheme.surface,
      elevation: 0,
      titleSpacing: 0,
      toolbarHeight: 70,
      automaticallyImplyLeading: false,
      title: Row(
        children: [
          Expanded(
            child: Container(
              height: 40,
              margin: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  Icon(Icons.search, color: isDark ? const Color(0xFFB0B0B0) : Colors.grey, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: searchProvider.searchController,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: '搜索对话',
                        hintStyle: TextStyle(
                          color: isDark ? const Color(0xFF757575) : Colors.grey,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 7,
                          horizontal: 8,
                        ),
                      ),
                      style: TextStyle(fontSize: 16, color: theme.colorScheme.onSurface),
                    ),
                  ),
                  if (searchProvider.hasQuery)
                    IconButton(
                      icon: Icon(
                        Icons.close,
                        size: 20,
                        color: isDark ? const Color(0xFFB0B0B0) : Colors.grey,
                      ),
                      onPressed: searchProvider.clearSearch,
                    ),
                ],
              ),
            ),
          ),
          TextButton(
            onPressed: searchProvider.navigateBack,
            child: Text(
              '取消',
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(70);
}
