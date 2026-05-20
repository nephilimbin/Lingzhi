import 'dart:typed_data';

/// 统一音频配置类
///
/// 提供所有音频相关组件的统一配置，避免重复定义
class AudioConfig {
  // 私有构造函数，防止实例化
  AudioConfig._();

  // 音频格式配置
  static const int sampleRate = 16000; // 采样率：16000Hz
  static const int channels = 1; // 声道：单声道
  static const int bitsPerSample = 16; // 位深度：16-bit
  static const int frameDuration = 60; // 帧时长：60毫秒
  static const int frameSize = 960; // 帧大小：60ms * 16000Hz / 1000
  static const int frameSizeBytes = frameSize * 2; // 帧大小字节：960 * 2

  // TTS音频参数配置（与后端保持一致）
  static const int ttsSampleRate = 16000; // TTS采样率：16000Hz
  static const int ttsChannels = 1; // TTS声道数：单声道

  // 音频播放配置
  static const int playbackBufferSize = 4096; // 播放缓冲区大小
  static const int maxQueueSize = 100; // 最大队列长度

  // 音频编码配置
  static const int opusBitrate = 32000; // Opus编码比特率
  static const int opusComplexity = 10; // Opus编码复杂度

  // 网络配置
  static const int websocketTimeout = 30; // WebSocket超时时间（秒）
  static const int reconnectInterval = 5; // 重连间隔（秒）

  // 调试配置
  static const bool enableAudioLogging = true; // 启用音频日志
  static const int logLevel = 1; // 日志级别

  /// 获取音频格式描述字符串
  static String get formatDescription {
    return '${sampleRate}Hz/${bitsPerSample}bit/${channels}ch';
  }

  /// 获取帧时长描述
  static String get frameDurationDescription {
    return '${frameDuration}ms';
  }

  /// 验证PCM数据格式
  static bool validatePcmFormat(Uint8List pcmData) {
    if (pcmData.isEmpty) {
      return false;
    }
    if (pcmData.length % 2 != 0) {
      return false; // 16-bit需要偶数长度
    }
    return true;
  }

  /// 计算PCM数据的时长（毫秒）
  static double calculatePcmDuration(Uint8List pcmData) {
    final sampleCount = pcmData.length ~/ 2; // 16-bit = 2 bytes per sample
    return (sampleCount / sampleRate) * 1000;
  }

  /// 计算需要的帧数
  static int calculateFrameCount(Uint8List pcmData) {
    final sampleCount = pcmData.length ~/ 2;
    return (sampleCount / frameSize).ceil();
  }

  /// 获取音频配置信息（用于调试）
  static Map<String, dynamic> getDebugInfo() {
    return {
      'sampleRate': sampleRate,
      'channels': channels,
      'bitsPerSample': bitsPerSample,
      'frameDuration': frameDuration,
      'frameSize': frameSize,
      'frameSizeBytes': frameSizeBytes,
      'ttsSampleRate': ttsSampleRate,
      'ttsChannels': ttsChannels,
      'formatDescription': formatDescription,
      'frameDurationDescription': frameDurationDescription,
    };
  }
}
