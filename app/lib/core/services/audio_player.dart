import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:synchronized/synchronized.dart';
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';
import 'dart:collection';
import 'package:opus_dart/opus_dart.dart';
import 'package:ai_assistant/core/utils/app_logger.dart';
import 'package:ai_assistant/core/services/audio_config.dart';
import 'package:ai_assistant/core/services/audio_service.dart';
import 'package:ai_assistant/core/services/audio_instant.dart';

/// 音频播放器类 - 专门处理音频播放功能
/// 从AudioService中分离出来的播放相关功能
/// 完全实例化管理，支持多个独立播放器实例
class AudioPlayer {
  // 播放器状态管理
  bool _isPlayerInitialized = false;
  bool _isPlaying = false; // 业务播放状态 - 用户控制
  bool _isMuted = false; // 静音状态
  bool _isSystemActive = true; // 系统活跃状态 (iOS生命周期)

  // 缓冲区状态跟踪
  int _lastRemainingFrames = 0;

  // 音频数据管理
  final Queue<Uint8List> _audioQueue = Queue<Uint8List>();
  final Lock _audioSessionLock = Lock();
  final SimpleOpusDecoder _decoder = SimpleOpusDecoder(
    sampleRate: AudioConfig.sampleRate,
    channels: AudioConfig.channels,
  );

  // 实例构造函数
  AudioPlayer();

  /// 实例初始化方法
  Future<bool> initialize() async {
    try {
      // 使用synchronized保护初始化过程
      await _audioSessionLock.synchronized(() async {
        // 双重检查，防止在等待锁的过程中状态已改变
        if (_isPlayerInitialized) {
          return;
        }
        try {
          // 1. 配置 flutter_pcm_sound
          await setFlutterPcmSoundConfig();
          _isPlayerInitialized = true;
          logI('PCM播放器初始化成功，使用官方缓冲机制');
        } catch (e) {
          logE('PCM播放器初始化失败: $e');
          // 初始化失败时，重置状态
          _isPlayerInitialized = false;
          rethrow;
        }
      });
      return true;
    } catch (e) {
      logE('播放器实例初始化失败: $e');
      return false;
    }
  }

  /// 设置FlutterPcmSound配置
  ///
  /// 使用 playback 类别以获得与手机媒体播放一致的音量
  /// 这是 flutter_pcm_sound 推荐的纯播放模式
  Future<void> setFlutterPcmSoundConfig() async {
    try {
      await FlutterPcmSound.setup(
        sampleRate: AudioConfig.sampleRate,
        channelCount: AudioConfig.channels,
        // playback: 纯播放模式，音量与手机媒体播放一致
        iosAudioCategory: IosAudioCategory.playback,
      );
      // 设置缓冲阈值
      await FlutterPcmSound.setFeedThreshold(AudioConfig.sampleRate ~/ 10);
      // 设置喂料回调
      FlutterPcmSound.setFeedCallback(_onFeedCallback);
    } catch (e) {
      logE('设置FlutterPcmSound配置失败: $e');
    }
  }

  /// 实例销毁方法
  Future<void> dispose() async {
    // 停止播放
    try {
      // 先停止播放
      await stopPlaybackAudio();
      // 等待10ms确保播放器状态已更新
      Future.delayed(const Duration(milliseconds: 10));
      logI('播放已停止');
    } catch (e) {
      logE('停止播放时出错: $e');
    }

    // 重置所有状态
    _isPlaying = false;
    _isPlayerInitialized = false;
    _isSystemActive = true;
    _isMuted = false;
    _lastRemainingFrames = 0;

    logI('播放器资源释放完成');
  }

  /// 统一音频播放接口 - 不自动设置播放状态
  Future<void> playbackAudio({
    required Uint8List audioData,
    AudioFormat format = AudioFormat.opus,
    bool enableWebRTC = true,
    AudioPlayContext? context,
  }) async {
    try {
      // 数据有效性检查
      if (audioData.isEmpty) {
        logW('收到空的音频数据，跳过音频播放');
        return;
      }

      // 确保播放器已初始化
      if (!_isPlayerInitialized) {
        await initialize();
      }

      // 播放器在需要投喂时启动
      if (_isPlaying) {
        FlutterPcmSound.start();
      }

      // 处理音频数据
      Uint8List? pcmData = await _decodeAudioData(audioData, format);
      if (pcmData == null) {
        logE('音频数据处理失败');
        return;
      }

      // 添加到队列
      if (!_isPlaying || _isMuted) {
        logI('播放状态不满足，跳过音频播放 (isPlaying: $_isPlaying, isMuted: $_isMuted)');
        return;
      } else {
        // 记录播放请求信息
        logI('收到音频播放数据: ${audioData.length} , 音频队列长度: ${_audioQueue.length}');
        _audioQueue.add(pcmData);
      }
    } catch (e) {
      logE('播放音频数据失败: $e');
    }
  }

  /// 处理不同音频格式为PCM
  Future<Uint8List?> _decodeAudioData(
    Uint8List audioData,
    AudioFormat format,
  ) async {
    switch (format) {
      case AudioFormat.opus:
        return await _decodeOpusData(audioData);
      case AudioFormat.pcm:
        return audioData;
      default:
        logE('不支持的音频格式: $format');
        return null;
    }
  }

  /// 解码Opus数据为PCM
  Future<Uint8List?> _decodeOpusData(Uint8List opusData) async {
    try {
      // 在 macOS 上，如果 Opus 库没有正确初始化，直接返回 null
      if (Platform.isMacOS) {
        logI('macOS 平台尝试解码 Opus 数据, 长度: ${opusData.length}');
        try {
          final pcmData = _decoder.decode(input: opusData);
          if (pcmData.isEmpty) {
            logI('macOS 平台 Opus 解码返回空数据');
            return null;
          }

          // 将 Int16List 转换为 Uint8List
          final Uint8List pcmBytes = Uint8List(pcmData.length * 2);
          final byteData = ByteData.view(pcmBytes.buffer);
          for (var i = 0; i < pcmData.length; i++) {
            byteData.setInt16(i * 2, pcmData[i], Endian.little);
          }

          logI('macOS 平台 Opus 解码成功，PCM数据长度: ${pcmBytes.length}');
          return pcmBytes;
        } catch (e) {
          logE('macOS 平台 Opus 解码失败: $e');
          return null;
        }
      }

      // 其他平台的正常解码逻辑
      final pcmData = _decoder.decode(input: opusData);
      if (pcmData.isEmpty) {
        return null;
      }

      // 将 Int16List 转换为 Uint8List
      final Uint8List pcmBytes = Uint8List(pcmData.length * 2);
      final byteData = ByteData.view(pcmBytes.buffer);
      for (var i = 0; i < pcmData.length; i++) {
        byteData.setInt16(i * 2, pcmData[i], Endian.little);
      }

      return pcmBytes;
    } catch (e, stackTrace) {
      logE('Opus解码失败: $e, stackTrace: ${stackTrace.toString()}');
      return null;
    }
  }

  /// 将 Uint8List 转换为 Int16List
  List<int> _convertUint8ToInt16(Uint8List uint8Data) {
    final int16List = <int>[];

    // 确保数据长度是偶数（每个16位样本需要2个字节）
    final length = uint8Data.length & ~1;

    for (int i = 0; i < length; i += 2) {
      // 小端序：低字节在前，高字节在后
      final int16Sample = uint8Data[i] | (uint8Data[i + 1] << 8);

      // 转换为有符号16位整数
      final signedSample =
          int16Sample > 32767 ? int16Sample - 65536 : int16Sample;
      int16List.add(signedSample);
    }

    return int16List;
  }

  /// 音频喂料回调函数
  void _onFeedCallback(int remainingFrames) {
    _lastRemainingFrames = remainingFrames;

    // 检查是否需要喂料
    if (!_isPlaying || _isMuted) {
      return;
    }

    // 如果有音频数据在队列中，立即喂料
    // _feedNextChunk();
    if (_audioQueue.isNotEmpty) {
      _feedNextChunk();
    } else {
      logI('音频队列为空，播放器将自然停止');
    }
  }

  /// 立即喂料下一个音频块 - 官方模式
  Future<void> _feedNextChunk() async {
    if (_audioQueue.isEmpty) {
      return;
    }

    try {
      // 取出音频数据
      final audioData = _audioQueue.removeFirst();

      // 解码为PCM数据
      final int16Data = _convertUint8ToInt16(audioData);

      // 立即喂料给播放器
      if (_isPlaying && !_isMuted) {
        await FlutterPcmSound.feed(PcmArrayInt16.fromList(int16Data));
      } else {
        _audioQueue.clear(); // 清空音频队列
      }
    } catch (e) {
      logE('喂料失败: $e');
    }
  }

  /// 检查是否正在播放
  bool get isPlaying => _isPlaying;

  /// 检查播放器是否已初始化
  bool get isInitialized => _isPlayerInitialized;

  /// 检查系统是否激活
  bool get isSystemActive => _isSystemActive;

  /// 获取静音状态
  bool get isMuted => _isMuted;

  /// 获取缓冲区状态
  int get remainingFrames => _lastRemainingFrames;

  /// 获取队列状态
  int get queueLength => _audioQueue.length;

  /// 设置播放状态 - 业务层控制
  void setPlaybackState(bool isPlaying) {
    // 增加锁
    try {
      logI('播放状态变更: $_isPlaying -> $isPlaying');
      _isPlaying = isPlaying;
      _audioQueue.clear(); // 清空音频队列
    } catch (e) {
      logE('设置播放状态失败: $e');
    }
  }

  /// 设置静音状态
  void setMuteState(bool muted) {
    // 增加锁
    try {
      logI('AudioPlayer静音状态变更: $_isMuted -> $muted');
      _isMuted = muted;
      _audioQueue.clear(); // 清空音频队列
    } catch (e) {
      logE('设置静音状态失败: $e');
    }
  }

  /// 中断播放 - 用户点击静音按钮触发
  Future<void> stopPlaybackAudio() async {
    // 立即设置播放状态
    _isPlaying = false;

    // 清空音频队列
    _audioQueue.clear();

    logI('播放已中断，队列已清空');
  }
}
