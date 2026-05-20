import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:record/record.dart' as record_lib;
import 'package:permission_handler/permission_handler.dart';
import 'package:opus_dart/opus_dart.dart';
import 'package:ai_assistant/core/utils/app_logger.dart';
import 'package:ai_assistant/core/services/audio_config.dart' as config;

/// 音频录音器类 - 专门处理音频录制功能
///
/// 职责：
/// - 录音器初始化和管理
/// - 权限管理和音频会话配置
/// - 录音控制和状态管理
/// - 音频流处理和Opus编码
///
/// 音频格式统一：16000Hz/16-bit/单声道/60ms帧
class AudioRecorder {
  // 实例化支持
  AudioRecorder();

  // 录音器核心组件
  final record_lib.AudioRecorder _audioRecorder = record_lib.AudioRecorder();

  // 状态管理
  bool _isRecorderInitialized = false;
  bool _isRecording = false;

  // 音频流处理
  StreamController<Uint8List> _audioStreamController =
      StreamController<Uint8List>.broadcast();

  // Opus编码器
  final _encoder = SimpleOpusEncoder(
    sampleRate: config.AudioConfig.sampleRate,
    channels: config.AudioConfig.channels,
    application: Application.audio,
  );

  // Opus缓冲区管理
  List<int> _opusBuffer = [];
  static const int _frameSizeBytes = config.AudioConfig.frameSizeBytes;

  // 预创建的录音配置（避免在startRecording时重复创建）
  record_lib.RecordConfig? _preCreatedRecordConfig;

  /// 获取音频流
  Stream<Uint8List> get audioStream {
    // 如果StreamController已关闭，重新创建
    if (_audioStreamController.isClosed) {
      logI('audioStream: StreamController已关闭，重新创建');
      _audioStreamController = StreamController<Uint8List>.broadcast();
      logI('audioStream: StreamController已重新创建');
    }
    return _audioStreamController.stream;
  }

  /// 检查是否已初始化
  bool get isInitialized => _isRecorderInitialized;

  /// 检查是否正在录音
  bool get isRecording => _isRecording;

  
  /// 初始化音频录制器
  Future<void> initRecorder() async {
    logI('开始初始化录音器');

    // 如果StreamController已关闭，重新创建
    if (_audioStreamController.isClosed) {
      logI('StreamController已关闭，重新创建');
      _audioStreamController = StreamController<Uint8List>.broadcast();
      logI('StreamController已重新创建');
    }

    // 在 macOS 上跳过权限请求，因为 permission_handler 插件不支持 macOS
    if (!Platform.isMacOS) {
      // 更积极地请求所有可能需要的权限
      if (Platform.isAndroid) {
        logI('请求Android所需的所有权限');
        Map<Permission, PermissionStatus> statuses =
            await [
              Permission.microphone,
              Permission.storage,
              Permission.manageExternalStorage,
              Permission.bluetooth,
              Permission.bluetoothConnect,
              Permission.bluetoothScan,
            ].request();

        logI('权限状态:');
        statuses.forEach((permission, status) {
          logI('$permission: $status');
        });

        if (statuses[Permission.microphone] != PermissionStatus.granted) {
          logE('麦克风权限被拒绝');
          throw Exception('需要麦克风权限');
        }
      } else {
        // iOS/其他平台只请求麦克风权限
        final status = await Permission.microphone.request();
        if (status != PermissionStatus.granted) {
          logE('麦克风权限被拒绝');
          throw Exception('需要麦克风权限');
        }
      }
    } else {
      logI('macOS 平台跳过权限请求');
    }

    // 检查是否可用
    final isAvailable = await _audioRecorder.isEncoderSupported(
      record_lib.AudioEncoder.pcm16bits,
    );
    logI('PCM16编码支持状态: $isAvailable');

    
    // 预创建录音配置对象，优化startRecording性能
    _preCreatedRecordConfig = record_lib.RecordConfig(
      encoder: record_lib.AudioEncoder.pcm16bits, // 16-bit PCM
      sampleRate: config.AudioConfig.sampleRate,
      numChannels: config.AudioConfig.channels,
    );
    logI('录音配置对象已预创建（${config.AudioConfig.formatDescription}）');

    _isRecorderInitialized = true;
    logI('录音器初始化成功');
  }

  /// 开始录音
  Future<void> startRecording() async {
    if (!_isRecorderInitialized) {
      await initRecorder();
    }

    // 防止重复启动录音
    if (_isRecording) {
      logI('录音已经在进行中，跳过重复启动');
      return;
    }

    try {
      // 确保麦克风权限已获取（仅做快速检查，因为初始化时已验证）
      final status = await Permission.microphone.status;

      if (status != PermissionStatus.granted) {
        final result = await Permission.microphone.request();
        if (result != PermissionStatus.granted) {
          logE('麦克风权限被拒绝，无法开始录音');
          return;
        }
      }

      // 使用预创建的录音配置对象，提高性能
      if (_preCreatedRecordConfig == null) {
        logE('录音配置对象未预创建，重新创建');
        _preCreatedRecordConfig = record_lib.RecordConfig(
          encoder: record_lib.AudioEncoder.pcm16bits,
          sampleRate: config.AudioConfig.sampleRate,
          numChannels: config.AudioConfig.channels,
        );
      }

      // 尝试直接使用音频流
      try {
        final stream = await _audioRecorder.startStream(
          _preCreatedRecordConfig!,
        );
        logI('录音流配置完成（使用预创建配置，${config.AudioConfig.formatDescription}）');

        _isRecording = true;
        logI('录音已开始');

        // 使用帧完整性编码处理音频流
        stream.listen(
          (data) async {
            if (data.isNotEmpty && data.length % 2 == 0) {
              // 使用帧完整性编码
              final opusPackets = await _encodeToOpusFrames(data);
              // 发送所有编码的opus包
              for (final opusData in opusPackets) {
                // 检查StreamController是否已关闭
                if (!_audioStreamController.isClosed) {
                  _audioStreamController.add(opusData);
                } else {
                  logW('StreamController已关闭，跳过音频数据发送');
                }
              }
            }
          },
          onError: (error) {
            logE('音频流错误: $error');
            _isRecording = false;
          },
          onDone: () async {
            logI('音频流结束');
            // 处理流结束时的剩余数据
            final remainingPackets = await _encodeToOpusFrames(
              Uint8List(0),
              endOfStream: true,
            );
            for (final opusData in remainingPackets) {
              // 检查StreamController是否已关闭
              if (!_audioStreamController.isClosed) {
                _audioStreamController.add(opusData);
              } else {
                logW('StreamController已关闭，跳过流结束时剩余数据发送');
              }
            }
            _isRecording = false;
          },
        );
      } catch (e) {
        logE('流式录音失败: $e');
        _isRecording = false;
        rethrow;
      }
    } catch (e, stackTrace) {
      logE('启动录音失败: $e');
      logE(stackTrace.toString());
      _isRecording = false;
      rethrow;
    }
  }

  /// 停止录音
  Future<String?> stopRecording() async {
    if (!_isRecorderInitialized) {
      logE('录音器未初始化，无法停止录音');
      return null;
    }

    // 防止重复停止录音
    if (!_isRecording) {
      logI('录音未在进行中，跳过重复停止');
      return null;
    }

    // 停止录音
    try {
      final path = await _audioRecorder.stop();
      _isRecording = false;

      // 处理停止录音时的剩余缓冲区数据
      try {
        final remainingPackets = await _encodeToOpusFrames(
          Uint8List(0),
          endOfStream: true,
        );
        for (final opusData in remainingPackets) {
          // 检查StreamController是否已关闭
          if (!_audioStreamController.isClosed) {
            _audioStreamController.add(opusData);
          } else {
            logW('StreamController已关闭，跳过剩余音频数据发送');
          }
        }
        logI('已处理录音停止时的剩余数据，包数: ${remainingPackets.length}');
      } catch (e) {
        logE('处理剩余缓冲区数据时出错: $e');
      }

      logI('录音已停止');
      return path;
    } catch (e) {
      logE('停止录音失败: $e');
      _isRecording = false;
      return null;
    }
  }

  /// 将PCM数据编码为Opus格式
  Future<List<Uint8List>> _encodeToOpusFrames(
    Uint8List pcmData, {
    bool endOfStream = false,
  }) async {
    try {
      // 添加音频数据质量检查
      if (pcmData.isEmpty && !endOfStream) {
        return [];
      }

      if (pcmData.isNotEmpty) {
        // 确保数据长度是偶数（16位采样需要2个字节）
        if (pcmData.length % 2 != 0) {
          logI('PCM数据长度异常(${pcmData.length})，丢弃最后一个字节');
          pcmData = pcmData.sublist(0, pcmData.length - 1);
        }

        // 将新的PCM数据添加到缓冲区
        _opusBuffer.addAll(pcmData);
      }

      List<Uint8List> opusPackets = [];

      // 处理所有完整的帧
      while (_opusBuffer.length >= _frameSizeBytes) {
        // 提取一个完整帧
        final frameBytes = Uint8List.fromList(
          _opusBuffer.take(_frameSizeBytes).toList(),
        );
        _opusBuffer = _opusBuffer.skip(_frameSizeBytes).toList();

        // 转换为Int16List进行编码
        final Int16List frameInt16 = Int16List.fromList(
          List.generate(
            frameBytes.length ~/ 2,
            (i) => (frameBytes[i * 2]) | (frameBytes[i * 2 + 1] << 8),
          ),
        );

        // 编码这一帧
        try {
          final opusData = Uint8List.fromList(
            _encoder.encode(input: frameInt16),
          );
          opusPackets.add(opusData);

          // logI('编码完整帧: ${frameInt16.length}样本 -> ${opusData.length}字节');
        } catch (e) {
          logE('编码帧失败: $e');
        }
      }

      // 流结束时处理剩余数据
      if (endOfStream && _opusBuffer.isNotEmpty) {
        logI('处理流结束，剩余${_opusBuffer.length}字节');

        // 创建最后一帧并用0填充
        final lastFrameBytes = Uint8List(_frameSizeBytes);
        for (int i = 0; i < _opusBuffer.length && i < _frameSizeBytes; i++) {
          lastFrameBytes[i] = _opusBuffer[i];
        }

        // 转换并编码最后一帧
        final Int16List lastFrameInt16 = Int16List.fromList(
          List.generate(
            lastFrameBytes.length ~/ 2,
            (i) => (lastFrameBytes[i * 2]) | (lastFrameBytes[i * 2 + 1] << 8),
          ),
        );

        try {
          final opusData = Uint8List.fromList(
            _encoder.encode(input: lastFrameInt16),
          );
          opusPackets.add(opusData);
          logI('编码最后帧: ${lastFrameInt16.length}样本 -> ${opusData.length}字节');
        } catch (e) {
          logE('编码最后帧失败: $e');
        }

        // 清空缓冲区
        _opusBuffer.clear();
      }

      return opusPackets;
    } catch (e, stackTrace) {
      logE('Opus编码失败: $e, stackTrace: ${stackTrace.toString()}');
      return [];
    }
  }

  
  /// 重置音频统计和opus缓冲区
  void _resetRecordAudioQueue() {
    _opusBuffer.clear();
    // logI('音频录制缓冲区已重置');
  }

  /// 实例化初始化
  Future<bool> initialize() async {
    try {
      await initRecorder();

      return true;
    } catch (e) {
      logE('录音器实例初始化失败: $e');
      return false;
    }
  }

  /// 实例化销毁
  Future<void> dispose() async {
    logI('开始释放录音器资源...');
    // 停止录音
    if (_isRecording) {
      try {
        await stopRecording();
        logI('录音已停止');
      } catch (e) {
        logE('停止录音时出错: $e');
      }
    }

    // 重置所有状态
    _isRecording = false;
    _isRecorderInitialized = false;

    // 清理预创建的录音配置对象
    _preCreatedRecordConfig = null;

    // 清理opus缓冲区和统计信息
    _resetRecordAudioQueue();

    // 关闭音频流控制器
    if (!_audioStreamController.isClosed) {
      _audioStreamController.close();
      logI('音频流控制器已关闭');
    }

    logI('录音器资源释放完成');
  }
}
