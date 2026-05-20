import 'dart:async';
import 'dart:typed_data';
import 'package:ai_assistant/core/utils/app_logger.dart';
import 'package:ai_assistant/core/services/audio_config.dart' as config;
import 'package:ai_assistant/core/services/audio_player.dart';
import 'package:ai_assistant/core/services/audio_recorder.dart';
import 'package:ai_assistant/core/services/audio_instant.dart';
import 'package:ai_assistant/core/services/audio_session_manager.dart';

class AudioPlayContext {
  final String? requestId;
  final String? currentRequestId;
  final bool isUserSpeaking;
  final bool isInVoiceCallMode;
  final String? mode; // "VoiceCall" or "Chat"

  const AudioPlayContext({
    this.requestId,
    this.currentRequestId,
    this.isUserSpeaking = false,
    this.isInVoiceCallMode = false,
    this.mode,
  });

  /// 预定义的常用context，避免重复创建
  static const AudioPlayContext empty = AudioPlayContext();

  /// 工厂方法：创建Chat模式的context
  factory AudioPlayContext.forChat({
    String? requestId,
    String? currentRequestId,
    bool isUserSpeaking = false,
  }) {
    return const AudioPlayContext(
      requestId: null,
      currentRequestId: null,
      isUserSpeaking: false,
      isInVoiceCallMode: false,
      mode: 'Chat',
    ).copyWith(
      requestId: requestId,
      currentRequestId: currentRequestId,
      isUserSpeaking: isUserSpeaking,
    );
  }

  /// 工厂方法：创建VoiceCall模式的context
  factory AudioPlayContext.forVoiceCall({
    String? requestId,
    String? currentRequestId,
    bool isUserSpeaking = false, // 保留参数兼容性，但在VoiceCall模式下不使用
  }) {
    return const AudioPlayContext(
      requestId: null,
      currentRequestId: null,
      isUserSpeaking: false, // VoiceCall模式下始终允许播放音频
      isInVoiceCallMode: true,
      mode: 'VoiceCall',
    ).copyWith(requestId: requestId, currentRequestId: currentRequestId);
  }

  /// 复制并修改部分属性
  AudioPlayContext copyWith({
    String? requestId,
    String? currentRequestId,
    bool? isUserSpeaking,
    bool? isInVoiceCallMode,
    String? mode,
  }) {
    return AudioPlayContext(
      requestId: requestId ?? this.requestId,
      currentRequestId: currentRequestId ?? this.currentRequestId,
      isUserSpeaking: isUserSpeaking ?? this.isUserSpeaking,
      isInVoiceCallMode: isInVoiceCallMode ?? this.isInVoiceCallMode,
      mode: mode ?? this.mode,
    );
  }
}

/// 音频服务统一管理类 - 统一管理player、recorder、webrtc的生命周期
/// 统一音频格式：16000Hz/16-bit/单声道，确保与后端要求一致
class AudioService {
  // 单例模式
  static final AudioService _instance = AudioService._internal();
  factory AudioService() => _instance;
  AudioService._internal();

  // 使用统一音频配置
  static const int sampleRate = config.AudioConfig.sampleRate;
  static const int channels = config.AudioConfig.channels;
  static const int frameDuration = config.AudioConfig.frameDuration;
  static const int bitsPerSample = config.AudioConfig.bitsPerSample;

  // 组件实例
  AudioPlayer? _audioPlayerInstance;
  AudioRecorder? _audioRecorderInstance;
  AudioSessionManager? _audioSessionInstance;

  // 统一状态管理
  bool _isSystemBusy = false;

  // requestId管理 - 用于静音状态切换
  String? _currentRequestId;
  String? _previousRequestId;
  bool _isMuteStateChanged = false;

  // 当前音频模式
  AudioMode _currentAudioMode = AudioMode.none;

  // 组件状态
  bool _isPlaybackActive = false;
  bool _isRecordingActive = false;

  // ============ 新的统一生命周期管理方法 ============

  /// 将 AudioMode 转换为 AudioSessionMode
  AudioSessionMode _convertToSessionMode(AudioMode mode) {
    switch (mode) {
      case AudioMode.chat:
        return AudioSessionMode.chat;
      case AudioMode.voiceCall:
        return AudioSessionMode.voiceCall;
      case AudioMode.none:
        // 这个不应该被调用，但提供默认值
        return AudioSessionMode.playback;
    }
  }

  /// 初始化音频系统（新的统一入口）
  Future<void> initializeAudioService({required AudioMode mode}) async {
    _isSystemBusy = true;

    try {
      logI('开始初始化音频系统，模式：$mode');

      // 1. 先清理现有状态
      await _cleanupAudioServiceState();

      // 2. 根据模式初始化组件
      await _initializeAudioComponents(mode);

      logI('音频系统初始化完成，模式：$mode');
    } catch (e) {
      logE('音频系统初始化失败：$e');
      await disposeAllComponents(); // 出错时强制清理
      rethrow;
    } finally {
      _isSystemBusy = false;
    }
  }

  /// 统一音频模式初始化
  Future<void> _initializeAudioComponents(AudioMode mode) async {
    logI('初始化音频模式：$mode');
    _currentAudioMode = mode;

    try {
      // 1. 初始化AudioSession
      await _initSessionComponent(mode);

      // 2. 初始化播放器
      await _initPlayerComponent();

      // 3. 初始化录音器
      await _initRecorderComponent();
      logI('音频系统初始化完成：$mode');
    } catch (e) {
      logE('音频组件初始化失败：$e');
      rethrow;
    }
  }

  Future<void> _initSessionComponent(AudioMode mode) async {
    try {
      _audioSessionInstance = AudioSessionManager();
      await _audioSessionInstance?.initialize();
      await _audioSessionInstance?.configure(_convertToSessionMode(mode));
      logI('AudioSession组件初始化完成');
    } catch (e) {
      logE('音频组件-AudioSession初始化失败：$e');
      rethrow;
    }
  }

  Future<void> _initPlayerComponent() async {
    try {
      _audioPlayerInstance = AudioPlayer();
      await _audioPlayerInstance?.initialize();
      _isPlaybackActive = true;
      logI('音频播放器初始化完成');
    } catch (e) {
      logE('音频组件-播放器初始化失败：$e');
      rethrow;
    }
  }

  Future<void> _initRecorderComponent() async {
    try {
      _audioRecorderInstance = AudioRecorder();
      await _audioRecorderInstance?.initialize();
      _isRecordingActive = true;
      logI('音频录音器初始化完成');
    } catch (e) {
      logE('音频组件-录音器初始化失败：$e');
      rethrow;
    }
  }

  /// 清理当前状态
  Future<void> _cleanupAudioServiceState() async {
    logI('清理当前音频系统状态');

    try {
      // 停止录音
      if (_isRecordingActive) {
        await _audioRecorderInstance?.stopRecording();
      }

      // 停止播放
      if (_isPlaybackActive) {
        await _audioPlayerInstance?.stopPlaybackAudio();
      }

      // 销毁实例
      await _audioPlayerInstance?.dispose();
      await _audioRecorderInstance?.dispose();

      // 清理实例引用
      _audioPlayerInstance = null;
      _audioRecorderInstance = null;

      logI('当前状态清理完成');
    } catch (e) {
      logE('清理当前状态失败：$e');
    }
  }

  // ============ 静态访问方法（向后兼容） ============

  /// 获取单例实例
  static AudioService get instance => _instance;

  /// 实例方法：验证音频播放准备状态
  bool validateAudioPlaybackReadiness(AudioPlayContext context) {
    // 基础技术层面检查
    if (_audioPlayerInstance?.isMuted ?? false) {
      logD('校验不通过音频:静音状态，禁止播放');
      return false;
    }

    // 静音状态变更检查 - 如果刚切换过静音状态，拒绝播放历史音频
    if (_isMuteStateChanged && _previousRequestId != null) {
      logD('校验不通过音频: 静音状态刚切换，拒绝播放历史音频');
      return false;
    }

    // requestId匹配检查 - 关键修复：使用AudioService的_currentRequestId而不是context.currentRequestId
    if (context.requestId != null && _currentRequestId != null) {
      if (context.requestId != _currentRequestId) {
        // 在VoiceCall模式下，如果用户不在说话，允许接受新的requestId
        logI(
          '校验不通过音频: ${context.requestId},音频ID: ${context.requestId}, 当前: $_currentRequestId',
        );
        if (context.isInVoiceCallMode && !context.isUserSpeaking) {
          logD('VoiceCall模式接受新的requestId');
        } else {
          return false;
        }
      }
    } else {
      logD(
        '校验不通过音频: requestId为空，音频ID: ${context.requestId}, 当前ID: $_currentRequestId',
      );
      return false;
    }

    // 用户说话状态检查
    if (context.isUserSpeaking) {
      logD('校验不通过音频:用户正在说话，禁止播放');
      return false;
    }

    // 所有检查通过，允许播放
    // logD('所有检查通过，允许播放');
    return true;
  }

  /// 实例方法：设置静音状态
  void setMuteState(bool muted) {
    if (muted != (_audioPlayerInstance?.isMuted ?? false)) {
      logI('静音状态变更: $muted，重置requestId');

      if (muted) {
        // 设置为静音时，重置requestId以阻止静音期间收到的音频包播放
        _previousRequestId = _currentRequestId;
        _currentRequestId = null;
        _isMuteStateChanged = true;
      } else {
        // 取消静音
        _previousRequestId = null;
        _isMuteStateChanged = false;
      }

      // 调用AudioPlayer设置静音状态
      _audioPlayerInstance?.setMuteState(muted);
    }
  }

  /// 设置当前requestId（用于新对话）
  void setCurrentRequestId(String? requestId) {
    _previousRequestId = _currentRequestId;
    _currentRequestId = requestId;

    // 当设置新的requestId时，清除静音状态变更标记
    if (requestId != null && _isMuteStateChanged) {
      logI('新对话开始，清除静音状态变更标记');
      _isMuteStateChanged = false;
    }

    logD('设置前requestId: $_previousRequestId, 设置后requestId: $requestId');
  }

  /// 获取当前requestId
  String? get currentRequestId => _currentRequestId;

  /// 实例方法：获取系统状态
  Map<String, dynamic> getSystemStatus() {
    return {
      'systemBusy': _isSystemBusy,
      'playbackActive': _isPlaybackActive,
      'recordingActive': _isRecordingActive,
      'audioMode': _currentAudioMode.name,
      'currentRequestId': _currentRequestId,
      'audioPlayerInstance': _audioPlayerInstance != null,
      'audioRecorderInstance': _audioRecorderInstance != null,
    };
  }

  /// 实例方法：统一音频播放接口
  Future<void> startPlayback({
    required Uint8List audioData,
    AudioFormat format = AudioFormat.opus,
    PlaybackMode mode = PlaybackMode.normal,
    bool enableWebRTC = true,
    AudioPlayContext? context,
  }) async {
    AudioPlayContext? updatedContext = context;

    // 先进行业务逻辑判断
    if (updatedContext == null ||
        !validateAudioPlaybackReadiness(updatedContext)) {
      logD('业务逻辑判断禁止播放，取消播放');
      return;
    }

    // 调用具体实现
    await _audioPlayerInstance?.playbackAudio(
      audioData: audioData,
      format: format,
      enableWebRTC: enableWebRTC,
      context: updatedContext,
    );
  }

  /// 实例方法：开始录音
  Future<void> startRecording() async {
    // 检查是否实例激活，如果没有则先初始化
    if (!_isRecordingActive) {}
    await _audioRecorderInstance?.startRecording();
  }

  /// 实例方法：停止录音
  Future<String?> stopRecording() async {
    return await _audioRecorderInstance?.stopRecording();
  }

  /// 实例方法：检查是否正在录音
  bool get isRecording => _audioRecorderInstance?.isRecording ?? false;

  /// 实例方法：检查是否正在播放
  bool get isPlaying => _audioPlayerInstance?.isPlaying ?? false;

  /// 实例方法：获取当前音频模式
  AudioMode get currentAudioMode => _currentAudioMode;

  /// 实例方法：获取音频流
  Stream<Uint8List> get audioStream =>
      _audioRecorderInstance?.audioStream ?? const Stream.empty();

  /// 统一强制清理所有音频资源
  Future<void> disposeAllComponents() async {
    try {
      // 1. 强制停止并清理播放器
      await _audioPlayerInstance?.dispose();
      await _audioRecorderInstance?.dispose();

      // 2. 清理实例引用
      _audioPlayerInstance = null;
      _audioRecorderInstance = null;

      // 3. 重置AudioSessionManager（关键修复）
      await _audioSessionInstance?.dispose();

      // 4. 重置系统状态
      _isSystemBusy = false;
      _isPlaybackActive = false;
      _isRecordingActive = false;

      logI('所有音频资源强制清理完成（包括AudioSessionManager重置）');
    } catch (e) {
      logE('强制清理失败: $e');
      rethrow;
    }
  }

  /// 设置播放状态 - 业务层调用
  void setPlaybackState(bool isPlaying) {
    try {
      _audioPlayerInstance?.setPlaybackState(isPlaying);
      logI('播放状态已设置: $isPlaying');
    } catch (e) {
      logE('设置播放状态失败: $e');
    }
  }

  /// 停止录音器组件
  Future<void> stopRecordingComponent() async {
    try {
      if (_isRecordingActive) {
        await _audioRecorderInstance?.stopRecording();
        logI('录音器组件已停止');
      }
    } catch (e) {
      logE('停止录音器组件失败: $e');
    }
  }

  /// TODO 暂时留着，调整voicecall模式时候删除
  Future<void> stopForForceInterrupt() async {
    await _audioPlayerInstance?.stopPlaybackAudio();
    await stopRecordingComponent();
  }

  /// 获取当前AudioSession模式
  AudioSessionMode? getCurrentAudioSessionMode() {
    return _audioSessionInstance?.currentMode;
  }

  /// 强制重新配置并验证AudioSession
  Future<bool> validateAudioSessionAndConfigure(AudioSessionMode mode) async {
    try {
      return await _audioSessionInstance?.validateAudioSessionAndConfigure(
            mode,
          ) ??
          false;
    } catch (e) {
      logE('强制配置并验证AudioSession失败: $e');
      return false;
    }
  }
}
