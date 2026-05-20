import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 主题提供者
///
/// 管理应用的主题模式，支持跟随系统、浅色和深色三种模式
class ThemeProvider extends ChangeNotifier {
  /// 主题模式存储键
  static const String _themeModeKey = 'theme_mode';

  /// 当前主题模式
  ThemeMode _themeMode = ThemeMode.system;

  /// 获取当前主题模式
  ThemeMode get themeMode => _themeMode;

  /// 是否为深色模式（仅用于兼容旧代码）
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  /// 获取主题模式的显示名称
  String get themeModeName {
    switch (_themeMode) {
      case ThemeMode.system:
        return '跟随系统';
      case ThemeMode.light:
        return '浅色模式';
      case ThemeMode.dark:
        return '深色模式';
    }
  }

  /// 构造函数，初始化时加载保存的主题模式
  ThemeProvider() {
    _loadThemeMode();
  }

  /// 从本地存储加载主题模式
  Future<void> _loadThemeMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final themeModeIndex = prefs.getInt(_themeModeKey) ?? 0;
      _themeMode = ThemeMode.values[themeModeIndex];
      notifyListeners();
    } catch (e) {
      // 如果加载失败，使用默认值
      _themeMode = ThemeMode.system;
      notifyListeners();
    }
  }

  /// 设置主题模式
  ///
  /// [mode] 要设置的主题模式
  Future<void> setThemeMode(ThemeMode mode) async {
    try {
      _themeMode = mode;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_themeModeKey, mode.index);
      notifyListeners();
    } catch (e) {
      // 保存失败时仍然更新状态
      notifyListeners();
    }
  }

  /// 切换主题模式（仅用于兼容旧代码）
  ///
  /// 按照 light -> dark -> light 的顺序切换
  Future<void> toggleTheme() async {
    final newMode = _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    await setThemeMode(newMode);
  }
}
