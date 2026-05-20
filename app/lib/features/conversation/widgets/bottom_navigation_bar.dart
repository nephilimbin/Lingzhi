import 'package:flutter/material.dart';
import 'package:ai_assistant/features/conversation/providers/home_provider.dart';

class CustomBottomNavigationBar extends StatelessWidget {
  final HomeProvider homeProvider;

  const CustomBottomNavigationBar({required this.homeProvider, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.grey.shade100,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
        boxShadow: [
          BoxShadow(
            color:
                isDark
                    ? Colors.black.withValues(alpha: 0.3)
                    : Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            spreadRadius: 0,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.only(
          top: 8,
          bottom: bottomPadding > 0 ? 16.0 : 8.0,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildNavItem(
              context: context,
              icon:
                  homeProvider.selectedIndex == 0
                      ? Icons.chat_bubble
                      : Icons.chat_bubble_outline,
              label: '消息',
              isSelected: homeProvider.selectedIndex == 0,
              selectedColor: theme.colorScheme.primary,
              unselectedColor:
                  isDark ? const Color(0xFF757575) : Colors.grey.shade600,
              onTap: () => homeProvider.setSelectedIndex(0),
            ),
            _buildNavItem(
              context: context,
              icon:
                  homeProvider.selectedIndex == 1
                      ? Icons.settings
                      : Icons.settings_outlined,
              label: '设置',
              isSelected: homeProvider.selectedIndex == 1,
              selectedColor: theme.colorScheme.primary,
              unselectedColor:
                  isDark ? const Color(0xFF757575) : Colors.grey.shade600,
              onTap: () => homeProvider.setSelectedIndex(1),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required BuildContext context,
    required IconData icon,
    required String label,
    required bool isSelected,
    required Color selectedColor,
    required Color unselectedColor,
    required VoidCallback onTap,
  }) {
    final color = isSelected ? selectedColor : unselectedColor;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: color,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Size get preferredSize => const Size.fromHeight(kBottomNavigationBarHeight);
}
