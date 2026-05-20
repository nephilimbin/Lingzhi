import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// 定义主要颜色
const Color primaryColor = Colors.black;
const Color accentColor = Colors.black;
const Color textColor = Colors.black;
const Color secondaryTextColor = Color(0xFF757575);
const Color backgroundColor = Colors.white;
const Color surfaceColor = Colors.white;
const Color errorColor = Colors.red;

// 不受主题影响的固定颜色
const Color userMessageBubbleColor = Colors.blue;
const Color userMessageTextColor = Colors.white;

// 获取用户消息气泡背景色（不随主题变化）
Color getUserMessageBubbleColor() => userMessageBubbleColor;

// 获取用户消息文本颜色（不随主题变化）
Color getUserMessageTextColor() => userMessageTextColor;

// 获取助手消息气泡背景色
Color getAssistantMessageBubbleColor(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark
      ? const Color(0xFF2A2A2A).withValues(alpha: 0.7)
      : const Color(0xFFF0F0F0);
}

// 获取助手消息文本颜色
Color getAssistantMessageTextColor(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? const Color(0xFFE0E0E0) : Colors.black87;
}

// Light theme
final ThemeData lightTheme = ThemeData(
  brightness: Brightness.light,
  primaryColor: primaryColor,
  colorScheme: const ColorScheme.light(
    primary: primaryColor,
    secondary: accentColor,
    surface: surfaceColor,
    error: errorColor,
    onPrimary: Colors.white,
    onSecondary: Colors.white,
    onSurface: textColor,
    onError: Colors.white,
  ),
  scaffoldBackgroundColor: backgroundColor,
  appBarTheme: const AppBarTheme(
    backgroundColor: backgroundColor,
    elevation: 0,
    iconTheme: IconThemeData(color: textColor),
    titleTextStyle: TextStyle(
      color: textColor,
      fontSize: 24,
      fontWeight: FontWeight.bold,
    ),
    systemOverlayStyle: SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  ),
  textTheme: const TextTheme(
    bodyLarge: TextStyle(color: textColor),
    bodyMedium: TextStyle(color: textColor),
    titleLarge: TextStyle(color: textColor, fontWeight: FontWeight.bold),
    titleMedium: TextStyle(color: textColor, fontWeight: FontWeight.bold),
    titleSmall: TextStyle(color: textColor, fontWeight: FontWeight.bold),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: primaryColor,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  ),
  floatingActionButtonTheme: const FloatingActionButtonThemeData(
    backgroundColor: primaryColor,
    foregroundColor: Colors.white,
  ),
  bottomNavigationBarTheme: const BottomNavigationBarThemeData(
    backgroundColor: Colors.white,
    selectedItemColor: primaryColor,
    unselectedItemColor: Color(0xFF757575),
    type: BottomNavigationBarType.fixed,
    elevation: 8,
  ),
  cardTheme: CardThemeData(
    color: Colors.white,
    elevation: 1,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(24),
      borderSide: BorderSide.none,
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  ),
);

// Dark theme (深色主题)
final ThemeData darkTheme = ThemeData(
  brightness: Brightness.dark,
  primaryColor: Colors.white,
  colorScheme: const ColorScheme.dark(
    primary: Colors.white,
    secondary: Color(0xFFB0B0B0),
    surface: Color(0xFF121212),
    error: errorColor,
    onPrimary: Colors.black,
    onSecondary: Colors.white,
    onSurface: Color(0xFFE0E0E0),
    onError: Colors.white,
    outline: Color(0xFF3A3A3A),
    outlineVariant: Color(0xFF2A2A2A),
  ),
  scaffoldBackgroundColor: const Color(0xFF121212),
  appBarTheme: const AppBarTheme(
    backgroundColor: Color(0xFF1E1E1E),
    elevation: 0,
    iconTheme: IconThemeData(color: Color(0xFFE0E0E0)),
    titleTextStyle: TextStyle(
      color: Color(0xFFE0E0E0),
      fontSize: 24,
      fontWeight: FontWeight.bold,
    ),
    systemOverlayStyle: SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  ),
  textTheme: const TextTheme(
    bodyLarge: TextStyle(color: Color(0xFFE0E0E0)),
    bodyMedium: TextStyle(color: Color(0xFFE0E0E0)),
    titleLarge: TextStyle(color: Color(0xFFE0E0E0), fontWeight: FontWeight.bold),
    titleMedium: TextStyle(color: Color(0xFFE0E0E0), fontWeight: FontWeight.bold),
    titleSmall: TextStyle(color: Color(0xFFE0E0E0), fontWeight: FontWeight.bold),
    bodySmall: TextStyle(color: Color(0xFFB0B0B0)),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: Colors.white,
      foregroundColor: Colors.black,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  ),
  floatingActionButtonTheme: const FloatingActionButtonThemeData(
    backgroundColor: Colors.white,
    foregroundColor: Colors.black,
  ),
  bottomNavigationBarTheme: const BottomNavigationBarThemeData(
    backgroundColor: Color(0xFF1E1E1E),
    selectedItemColor: Colors.white,
    unselectedItemColor: Color(0xFF757575),
    type: BottomNavigationBarType.fixed,
    elevation: 8,
  ),
  cardTheme: CardThemeData(
    color: const Color(0xFF1E1E1E),
    elevation: 1,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: const Color(0xFF2A2A2A),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(24),
      borderSide: BorderSide.none,
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    hintStyle: const TextStyle(color: Color(0xFF757575)),
  ),
  dividerTheme: const DividerThemeData(
    color: Color(0xFF3A3A3A),
    thickness: 1,
  ),
  dialogTheme: const DialogThemeData(
    backgroundColor: Color(0xFF1E1E1E),
    titleTextStyle: TextStyle(
      color: Color(0xFFE0E0E0),
      fontSize: 20,
      fontWeight: FontWeight.bold,
    ),
    contentTextStyle: TextStyle(color: Color(0xFFE0E0E0)),
  ),
  bottomSheetTheme: const BottomSheetThemeData(
    backgroundColor: Color(0xFF1E1E1E),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
  ),
  listTileTheme: const ListTileThemeData(
    iconColor: Color(0xFFE0E0E0),
    textColor: Color(0xFFE0E0E0),
  ),
  iconTheme: const IconThemeData(
    color: Color(0xFFE0E0E0),
  ),
);
