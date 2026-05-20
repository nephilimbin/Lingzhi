/// 音频模式枚举
///
/// 定义不同的音频系统工作模式：
/// - none: 无音频功能
/// - chat: 聊天模式（基础录音和播放）
/// - voiceCall: 语音通话模式（支持WebRTC AEC）
enum AudioMode {
  /// 无音频功能
  none,

  /// 聊天模式（基础录音和播放）
  chat,

  /// 语音通话模式（支持WebRTC AEC）
  voiceCall,
}

/// 音频格式枚举
enum AudioFormat {
  /// PCM原始格式
  pcm,

  /// Opus编码格式
  opus,

  /// WAV格式
  wav,
}

/// 播放模式枚举
enum PlaybackMode {
  /// 普通播放
  normal,

  /// 流式播放
  streaming,
}

/// 音频系统操作类型
enum AudioOperation {
  /// 空闲
  idle,

  /// 播放中
  playing,

  /// 录音中
  recording,

  /// 缓冲中
  buffering,

  /// 中断中
  interrupting,
}

/// 清理模式枚举
enum AudioCleanupMode {
  /// VoiceCall退出清理
  voiceCallExit,
}

/// 音频状态枚举
enum AudioState {
  /// 空闲
  idle,

  /// 初始化中
  initializing,

  /// 播放中
  playing,

  /// 录音中
  recording,

  /// 处理中
  processing,

  /// 错误状态
  error,
}
