import 'package:audio_session/audio_session.dart';
import 'package:ai_assistant/core/utils/app_logger.dart';

/// 音频会话模式枚举
enum AudioSessionMode {
  chat, // 聊天模式：支持播放和录音
  voiceCall, // 语音通话模式：支持双向通话
  playback, // 播放模式：仅播放音频
  recording, // 录音模式：仅录音
}

/// 音频会话管理器 - 统一管理iOS/Android音频会话配置
///
/// 职责：
/// - 统一管理AudioSession配置
/// - 提供不同模式的预配置
/// - 管理AudioSession生命周期
/// - 避免重复配置冲突
///
/// 音频格式统一：16000Hz/16-bit/单声道，确保与后端要求一致
class AudioSessionManager {
  static final AudioSessionManager _instance = AudioSessionManager._internal();
  factory AudioSessionManager() => _instance;
  AudioSessionManager._internal();

  // 状态管理
  AudioSessionMode? _currentMode;
  bool _isInitialized = false;
  AudioSession? _session;

  /// 获取当前配置模式
  AudioSessionMode? get currentMode => _currentMode;

  /// 检查是否已初始化
  bool get isInitialized => _isInitialized;

  /// 获取AudioSession实例
  AudioSession get session {
    if (_session == null) {
      throw Exception('AudioSession未初始化，请先调用initialize()');
    }
    return _session!;
  }

  /// 预定义配置 - 针对不同使用场景优化
  static final Map<AudioSessionMode, AudioSessionConfiguration>
  _configurations = {
    // 聊天模式：支持TTS播放和语音录音，平衡音质和性能
    AudioSessionMode.chat: AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
      avAudioSessionCategoryOptions:
          AVAudioSessionCategoryOptions.allowBluetooth |
          AVAudioSessionCategoryOptions.defaultToSpeaker, // 添加：确保音频从扬声器播放
      avAudioSessionMode: AVAudioSessionMode.voiceChat,
      androidAudioAttributes: AndroidAudioAttributes(
        contentType: AndroidAudioContentType.speech,
        usage: AndroidAudioUsage.voiceCommunication,
        flags: AndroidAudioFlags.audibilityEnforced,
      ),
      androidAudioFocusGainType:
          AndroidAudioFocusGainType.gainTransientExclusive,
      androidWillPauseWhenDucked: false,
    ),

    // 语音通话模式：优化实时通话，支持AEC和噪声抑制
    // Android使用media usage以获得更高的音量上限
    AudioSessionMode.voiceCall: AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
      avAudioSessionCategoryOptions:
          AVAudioSessionCategoryOptions.allowBluetooth |
          AVAudioSessionCategoryOptions.defaultToSpeaker,
      avAudioSessionMode: AVAudioSessionMode.voiceChat,
      androidAudioAttributes: AndroidAudioAttributes(
        contentType: AndroidAudioContentType.speech,
        usage: AndroidAudioUsage.media, // 使用媒体模式提高音量上限
        flags: AndroidAudioFlags.audibilityEnforced,
      ),
      androidAudioFocusGainType:
          AndroidAudioFocusGainType.gainTransientExclusive,
      androidWillPauseWhenDucked: false,
    ),

    // 播放模式：优化TTS音频播放质量
    AudioSessionMode.playback: AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playback,
      avAudioSessionCategoryOptions:
          AVAudioSessionCategoryOptions.allowBluetooth |
          AVAudioSessionCategoryOptions.mixWithOthers, // 添加：允许与其他音频混音
      avAudioSessionMode: AVAudioSessionMode.spokenAudio,
      androidAudioAttributes: AndroidAudioAttributes(
        contentType: AndroidAudioContentType.speech, // 修改：使用speech更符合TTS场景
        usage: AndroidAudioUsage.media, // 保持media以获得更大音量
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      androidWillPauseWhenDucked: false, // 修改：不暂停以保持连续播放
    ),

    // 录音模式：优化录音质量，减少干扰
    AudioSessionMode.recording: AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.record,
      avAudioSessionCategoryOptions:
          AVAudioSessionCategoryOptions.allowBluetooth,
      avAudioSessionMode: AVAudioSessionMode.spokenAudio,
      androidAudioAttributes: AndroidAudioAttributes(
        contentType: AndroidAudioContentType.speech,
        usage: AndroidAudioUsage.voiceCommunication,
        flags: AndroidAudioFlags.audibilityEnforced,
      ),
      androidAudioFocusGainType:
          AndroidAudioFocusGainType.gainTransientExclusive,
      androidWillPauseWhenDucked: false,
    ),
  };

  /// 初始化AudioSessionManager
  Future<void> initialize() async {
    if (_isInitialized) {
      logI('AudioSessionManager已初始化，跳过重复初始化');
      return;
    }

    try {
      logI('开始初始化AudioSessionManager');
      _session = await AudioSession.instance;
      _isInitialized = true;
      logI('AudioSessionManager初始化成功');
    } catch (e) {
      logE('AudioSessionManager初始化失败: $e');
      rethrow;
    }
  }

  /// 配置AudioSession为指定模式
  Future<void> configure(AudioSessionMode mode) async {
    if (!_isInitialized) {
      await initialize();
    }

    if (_currentMode == mode) {
      logD('AudioSession已经是$mode模式，跳过配置');
      return;
    }

    try {
      final config = _configurations[mode];

      if (config == null) {
        throw Exception('未找到$mode模式的配置');
      }
      await _session!.configure(config);
      _currentMode = mode;
      logI('AudioSession已成功配置为:$mode模式');
    } catch (e) {
      logE('配置AudioSession为:$mode模式失败: $e');
      rethrow;
    }
  }

  /// 验证当前AudioSession的实际配置是否与期望模式匹配
  Future<bool> _validateCurrentConfiguration(
    AudioSessionMode expectedMode,
  ) async {
    if (!_isInitialized || _session == null) {
      logW('AudioSessionManager未初始化，无法验证配置');
      return false;
    }

    try {
      // 检查模式匹配
      if (_currentMode != expectedMode) {
        logW('AudioSession模式不匹配: 当前=$_currentMode, 期望=$expectedMode');
        return false;
      }

      // 获取期望配置
      final expectedConfig = _configurations[expectedMode];
      if (expectedConfig == null) {
        logW('未找到$expectedMode模式的期望配置');
        return false;
      }

      // 获取当前实际配置
      final currentConfig = _session!.configuration;
      if (currentConfig == null) {
        logW('当前AudioSession配置为null，无法验证');
        return false;
      }

      final currentCategory = currentConfig.avAudioSessionCategory;
      final currentMode = currentConfig.avAudioSessionMode;
      printCurrentAudioSessionInfo();

      // 验证iOS配置
      if (expectedConfig.avAudioSessionCategory != null) {
        final expectedCategory = expectedConfig.avAudioSessionCategory!;
        if (currentCategory != expectedCategory) {
          logW('iOS音频类别不匹配: 当前=$currentCategory, 期望=$expectedCategory');
          return false;
        }
      }

      if (expectedConfig.avAudioSessionMode != null) {
        final expectedMode = expectedConfig.avAudioSessionMode!;
        if (currentMode != expectedMode) {
          logW('iOS音频模式不匹配: 当前=$currentMode, 期望=$expectedMode');
          return false;
        }
      }

      // 根据模式验证特定配置
      switch (expectedMode) {
        case AudioSessionMode.chat:
        case AudioSessionMode.voiceCall:
          // 聊天和语音通话模式需要支持播放和录音
          if (currentCategory != AVAudioSessionCategory.playAndRecord) {
            logW('聊天/通话模式需要playAndRecord类别，当前: $currentCategory');
            return false;
          }
          break;

        case AudioSessionMode.playback:
          // 播放模式只需要播放功能
          if (currentCategory != AVAudioSessionCategory.playback) {
            logW('播放模式需要playback类别，当前: $currentCategory');
            return false;
          }
          break;

        case AudioSessionMode.recording:
          // 录音模式只需要录音功能
          if (currentCategory != AVAudioSessionCategory.record) {
            logW('录音模式需要record类别，当前: $currentCategory');
            return false;
          }
          break;
      }

      logI('AudioSession详细配置验证通过，当前模式：$expectedMode');
      return true;
    } catch (e) {
      logE('验证AudioSession配置时出错: $e');
      return false;
    }
  }

  /// 验证配置
  Future<bool> validateAudioSessionAndConfigure(AudioSessionMode mode) async {
    try {
      // 验证配置是否生效
      final isValid = await _validateCurrentConfiguration(mode);

      if (isValid) {
        logI('AudioSession配置并验证成功:$mode');
        return true;
      } else {
        logW('AudioSession配置后验证失败,重新配置:$mode');
        // 重新配置
        await configure(mode);
        // 重新验证配置结果
        final revalidated = await _validateCurrentConfiguration(mode);
        if (revalidated) {
          logI('AudioSession重新配置验证成功:$mode');
        } else {
          logW('AudioSession重新配置后仍然验证失败:$mode');
        }
        return revalidated;
      }
    } catch (e) {
      logE('强制配置并验证AudioSession失败: $e');
      return false;
    }
  }

  /// 获取当前模式的中文描述
  String get currentModeDescription {
    switch (_currentMode) {
      case AudioSessionMode.chat:
        return '聊天模式';
      case AudioSessionMode.voiceCall:
        return '语音通话模式';
      case AudioSessionMode.playback:
        return '播放模式';
      case AudioSessionMode.recording:
        return '录音模式';
      case null:
        return '未配置';
    }
  }

  /// 打印当前AudioSession的详细信息（用于调试）
  Future<void> printCurrentAudioSessionInfo() async {
    if (!_isInitialized || _session == null) {
      logW('AudioSessionManager未初始化，无法获取信息');
      return;
    }

    try {
      final config = _session!.configuration;
      if (config == null) {
        logW('当前AudioSession配置为null');
        return;
      }

      logI('=== 当前AudioSession详细信息 ===');
      logI('音频类别: ${config.avAudioSessionCategory}');
      logI('音频模式: ${config.avAudioSessionMode}');
      logI('音频类别选项: ${config.avAudioSessionCategoryOptions}');
      logI('路由共享策略: ${config.avAudioSessionRouteSharingPolicy}');
      logI('激活选项: ${config.avAudioSessionSetActiveOptions}');
      logI('Android音频属性: ${config.androidAudioAttributes}');
      logI('Android音频焦点增益类型: ${config.androidAudioFocusGainType}');
      logI('Android被 Duck 时暂停: ${config.androidWillPauseWhenDucked}');
      logI('当前模式: $currentModeDescription');
      logI('================================');
    } catch (e) {
      logE('获取AudioSession信息时出错: $e');
    }
  }

  /// 销毁AudioSessionManager
  Future<void> dispose() async {
    try {
      logI('开始销毁AudioSessionManager');
      _currentMode = null;
      _isInitialized = false;
      _session = null;
      logI('AudioSessionManager销毁完成');
    } catch (e) {
      logE('销毁AudioSessionManager失败: $e');
    }
  }
}
