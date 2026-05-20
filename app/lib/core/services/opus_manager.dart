import 'dart:io';
import 'package:opus_flutter/opus_flutter.dart' as opus_flutter;
import 'package:opus_dart/opus_dart.dart';
import 'package:ai_assistant/core/utils/app_logger.dart';

/// Opus 编解码器管理器
/// 负责延迟初始化 Opus 库，避免应用启动时崩溃
class OpusManager {
  static OpusManager? _instance;
  bool _isInitialized = false;
  bool _isInitializing = false;
  String? _version;

  OpusManager._();

  static OpusManager get instance {
    _instance ??= OpusManager._();
    return _instance!;
  }

  /// 是否已初始化
  bool get isInitialized => _isInitialized;

  /// 是否正在初始化
  bool get isInitializing => _isInitializing;

  /// Opus 版本
  String? get version => _version;

  /// 初始化 Opus 库
  /// [force] 是否强制重新初始化
  Future<bool> initialize({bool force = false}) async {
    if (_isInitialized && !force) {
      logI('Opus 已经初始化，版本: $_version');
      return true;
    }

    if (_isInitializing) {
      logW('Opus 正在初始化中，请稍候...');
      // 等待初始化完成
      int attempts = 0;
      while (_isInitializing && attempts < 50) {
        await Future.delayed(const Duration(milliseconds: 100));
        attempts++;
      }
      return _isInitialized;
    }

    _isInitializing = true;

    try {
      logI('🎵 开始初始化 Opus 库...');

      // macOS 暂时跳过
      if (Platform.isMacOS) {
        logW('macOS 平台暂时跳过 Opus 初始化');
        _isInitializing = false;
        return false;
      }

      // iOS 平台特殊处理
      if (Platform.isIOS) {
        logI('iOS 平台初始化 Opus 库...');
        // 延迟执行，避免主线程阻塞
        await Future.delayed(const Duration(milliseconds: 100));
      }

      // 加载 Opus 库
      final library = await opus_flutter.load();
      initOpus(library);

      // 获取版本
      _version = getOpusVersion();
      _isInitialized = true;

      logI('✅ Opus 库初始化成功: $_version');
      return true;
    } catch (e, stackTrace) {
      logE('❌ Opus 库初始化失败', e, stackTrace);
      _isInitialized = false;
      return false;
    } finally {
      _isInitializing = false;
    }
  }

  /// 确保 Opus 已初始化，如果未初始化则尝试初始化
  /// 返回是否初始化成功
  Future<bool> ensureInitialized() async {
    if (_isInitialized) {
      return true;
    }
    return await initialize();
  }
}
