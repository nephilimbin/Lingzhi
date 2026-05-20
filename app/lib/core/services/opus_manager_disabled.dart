import 'package:flutter/material.dart';
import 'package:ai_assistant/core/utils/app_logger.dart';

/// Opus 编解码器管理器 - 禁用版本用于测试
/// 这个版本不导入任何 Opus 相关库，用于测试是否是 Opus 导致的崩溃
class OpusManagerDisabled {
  static OpusManagerDisabled? _instance;
  bool _isInitialized = false;
  String? _version;

  OpusManagerDisabled._();

  static OpusManagerDisabled get instance {
    _instance ??= OpusManagerDisabled._();
    return _instance!;
  }

  bool get isInitialized => _isInitialized;
  String? get version => _version;

  /// 初始化 Opus 库 - 禁用版本
  Future<bool> initialize({bool force = false}) async {
    if (_isInitialized && !force) {
      logI('Opus 已禁用（测试模式）');
      return true;
    }

    logW('⚠️ Opus 库已禁用，音频功能将不可用');
    _isInitialized = true;
    _version = "disabled";
    return true;
  }

  /// 确保 Opus 已初始化
  Future<bool> ensureInitialized() async {
    return _isInitialized ? true : await initialize();
  }
}
