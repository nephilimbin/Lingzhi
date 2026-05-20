import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:ai_assistant/core/utils/app_logger.dart';
import 'package:ai_assistant/core/services/websocket_manager.dart';
import 'package:ai_assistant/core/services/webrtc_config_service.dart';
import 'package:ai_assistant/features/telephony/providers/android_webrtc_handler.dart';
import 'package:ai_assistant/features/telephony/providers/ios_webrtc_handler.dart';

/// Telephony 状态管理器
/// 负责管理WebRTC连接、音频处理等所有状态和业务逻辑
/// WebSocket连接由外部传入的 WebSocketManager 管理
class TelephonyProvider extends ChangeNotifier {
  /// 构造函数
  ///
  /// [serverUrl] 外部传入的服务器地址 (HTTP协议)
  /// [webSocketManager] 外部传入的 WebSocketManager 实例
  /// [sessionId] 从外部传入的 session_id，用于 WebRTC 连接认证
  /// [context] BuildContext 上下文
  TelephonyProvider({
    required this.serverUrl,
    required DiyWebSocketManager webSocketManager,
    required String sessionId,
    required BuildContext context,
  }) : _webSocketManager = webSocketManager,
       _sessionId = sessionId,
       _context = context,
       _webrtcConfigService = WebRtcConfigService(serverUrl: serverUrl);

  /// 外部传入的服务器地址 (HTTP协议)
  final String serverUrl;

  // 外部依赖
  final DiyWebSocketManager _webSocketManager;
  // BuildContext 保留用于将来的功能（如显示对话框等）
  // ignore: unused_field
  final BuildContext _context;

  // WebRTC 配置服务
  final WebRtcConfigService _webrtcConfigService;
  WebRtcConfig? _cachedWebRtcConfig; // 缓存配置（应用生命周期内有效）

  // WebRTC相关
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  // 状态管理
  bool _isConnected = false;
  bool _isConnecting = false;
  String _connectionStatus = '未连接';

  // 音频状态管理
  bool _hasMicrophonePermission = false;
  bool _isRecording = false;
  bool _isMuted = false; // 静音状态
  bool _isReceivingAudio = false; // 接收音频状态（用于波形动画）
  String _audioStatus = '未初始化';
  String _lastAudioError = '';
  Timer? _audioLevelTimer;
  bool _isPermanentlyDenied = false; // 权限是否被永久拒绝

  // 视频状态管理
  bool _isVideoEnabled = false; // Android和iOS都默认禁用视频功能
  MediaStreamTrack? _videoTrack; // 视频轨道引用

  // 平台特定 WebRTC 处理器
  AndroidWebRTCHandler? _androidHandler;
  IOSWebRTCHandler? _iosHandler;

  // 数据通道
  RTCDataChannel? _dataChannel;
  int _audioFrameCount = 0;
  Timer? _audioStatsTimer;

  // ICE 候选收集相关
  Completer<void>? _iceGatheringCompleter;
  int _iceCandidateCount = 0;
  final List<RTCIceCandidate> _pendingIceCandidates = <RTCIceCandidate>[];
  Timer? _iceCandidateBatchTimer;
  bool _isIceGatheringComplete = false;

  // 异步操作取消管理
  bool _isCancelling = false;
  bool _isDisposed = false; // 防止在 dispose 后继续操作

  // 请求去重和限流
  String? _lastOfferSent;
  int _connectionAttempts = 0;
  static const int _maxConnectionAttempts = 5; // 增加最大重试次数

  // 优化的重试间隔配置（毫秒）- 快速递增策略
  static const List<int> _retryIntervals = <int>[500, 1000, 2000, 5000, 10000];

  // Session ID存储
  String? _sessionId; // ✅ 存储从WebSocket获得的session_id

  // Getters
  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;
  String get connectionStatus => _connectionStatus;
  bool get hasMicrophonePermission => _hasMicrophonePermission;
  bool get isRecording => _isRecording;
  bool get isMuted => _isMuted;
  bool get isReceivingAudio => _isReceivingAudio;
  String get audioStatus => _audioStatus;
  String get lastAudioError => _lastAudioError;
  String? get sessionId => _sessionId;
  bool get isPermanentlyDenied => _isPermanentlyDenied;
  bool get isVideoEnabled => _isVideoEnabled;
  RTCVideoRenderer get localRenderer => _localRenderer;

  /// 设置Session ID
  ///
  /// 当外部WebSocketManager收到包含session_id的消息时调用此方法
  /// [sessionId] 从WebSocket消息中获取的session_id
  void setSessionId(String sessionId) {
    if (_sessionId != sessionId) {
      final String? oldSessionId = _sessionId;
      _sessionId = sessionId;
      logI('✅ Session ID已更新: $oldSessionId → $_sessionId');
      notifyListeners();
    }
  }

  /// 检查麦克风权限状态（不请求权限）
  /// 使用更安全的方式，避免权限状态变化时系统崩溃
  Future<bool> checkMicrophonePermission() async {
    if (_isDisposed) {
      return false;
    }

    // 添加延迟，避免在权限状态变化时立即检查
    await Future.delayed(const Duration(milliseconds: 50));

    try {
      final status = await Permission.microphone.status;
      _hasMicrophonePermission = status == PermissionStatus.granted;
      _isPermanentlyDenied = status == PermissionStatus.permanentlyDenied;
      return _hasMicrophonePermission;
    } catch (e) {
      // 权限检查失败，使用 isGranted 属性作为备用
      await Future.delayed(const Duration(milliseconds: 50));
      final granted = await Permission.microphone.isGranted;
      _hasMicrophonePermission = granted;
      return granted;
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _cleanup();
    super.dispose();
  }

  /// 安全的通知监听器方法，防止在 dispose 后调用
  @override
  void notifyListeners() {
    if (!_isDisposed) {
      super.notifyListeners();
    }
  }

  /// 初始化视频渲染器
  Future<void> _initializeRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  /// 请求必要的权限
  Future<void> _requestPermissions() async {
    try {
      // 摄像头权限（虽然我们不用视频）
      try {
        await Permission.camera.request();
      } catch (_) {}

      // 麦克风权限 - 直接请求，不先检查状态
      logI('[系统] 正在请求麦克风权限...');
      final PermissionStatus micStatus = await Permission.microphone.request();
      logI('[系统] 权限请求结果: ${micStatus.name}');

      _hasMicrophonePermission = micStatus == PermissionStatus.granted;
      _audioStatus = _hasMicrophonePermission ? '权限已授予' : '麦克风权限被拒绝';
      _isPermanentlyDenied = micStatus == PermissionStatus.permanentlyDenied;

      if (!_hasMicrophonePermission) {
        _lastAudioError = '麦克风权限被拒绝，请在设置中手动开启';
        logW('[警告] $_lastAudioError');
      } else {
        logI('[系统] 麦克风权限已授予');
      }

      notifyListeners();
    } catch (e) {
      _audioStatus = '权限检查失败';
      _lastAudioError = '权限检查失败: $e';
      _hasMicrophonePermission = false;
      logE('[错误] 权限检查失败: $e');
      notifyListeners();
    }
  }

  /// 创建WebRTC连接配置
  /// 从后端获取全局配置，失败时抛出异常
  Future<Map<String, dynamic>> createRtcConfiguration() async {
    // 如果有缓存的配置，使用缓存
    if (_cachedWebRtcConfig != null) {
      return _cachedWebRtcConfig!.toRTCConfiguration();
    }

    // 从后端获取全局配置
    final config = await _webrtcConfigService.fetchWebRtcConfig();
    if (config != null) {
      _cachedWebRtcConfig = config;
      logI('✅ 使用从后端获取的全局 WebRTC 配置');
      return config.toRTCConfiguration();
    }

    // 配置获取失败，抛出异常
    logE('❌ 无法获取 WebRTC 配置');
    throw Exception('无法获取 WebRTC 配置，请检查网络连接或后端服务');
  }

  /// 连接到WebRTC服务器 - 使用外部WebSocketManager的session_id
  Future<void> connectToServer() async {
    // 检查是否已经在连接或已连接
    if (_isConnecting || _isConnected) {
      return;
    }

    // 检查连接尝试次数
    if (_connectionAttempts >= _maxConnectionAttempts) {
      logE('[错误] ❌ 连接尝试次数已达上限 ($_maxConnectionAttempts)，请稍后再试');
      return;
    }

    // 确保外部 WebSocket 已连接
    if (!_webSocketManager.isConnected) {
      logE('[错误] ❌ 外部WebSocket未连接，无法建立WebRTC连接');
      _connectionStatus = 'WebSocket未连接';
      notifyListeners();
      return;
    }

    // 从外部 WebSocketManager 获取 session_id
    // 如果没有，我们需要从 WebSocket 消息中获取
    if (_sessionId == null || _sessionId!.isEmpty) {
      logW('[警告] ⚠️ Session ID 尚未获取，等待WebSocket消息...');
      _connectionStatus = '等待Session ID';
      notifyListeners();

      // 等待一小段时间让 WebSocket 建立连接并接收消息
      await Future<void>.delayed(const Duration(milliseconds: 500));

      // 再次检查
      if (_sessionId == null || _sessionId!.isEmpty) {
        logE('[错误] ❌ 无法获取session_id，请确保WebSocket已建立连接');
        _connectionStatus = '无法获取Session ID';
        notifyListeners();
        return;
      }
    }

    logI('✅ 使用session_id: $_sessionId');

    _connectionAttempts++;
    _isCancelling = false;
    _isConnecting = true;
    _connectionStatus =
        '正在连接 WebRTC... (尝试 $_connectionAttempts/$_maxConnectionAttempts)';
    notifyListeners();

    try {
      final DateTime startTime = DateTime.now();
      logI('🚀 开始WebRTC连接流程 (第 $_connectionAttempts 次尝试)...');

      // 验证session_id
      if (_sessionId == null || _sessionId!.isEmpty) {
        throw Exception('session_id无效');
      }
      logI('🆔 使用session_id: $_sessionId');

      // 检查取消状态
      if (_isCancelling) {
        logI('连接已取消');
        return;
      }

      // 重置ICE相关状态
      _resetIceState();

      // 配置音频会话
      logI('🎵 配置音频会话...');
      await _configureAudioSession();

      // === 新增：预加载全局 WebRTC 配置 ===
      await _preloadWebRtcConfig();

      // 创建WebRTC连接
      await _createPeerConnection();
      if (_isCancelling) {
        return;
      }

      // 获取本地音频流
      await _getUserMedia();
      if (_isCancelling) {
        return;
      }

      // 创建WebRTC offer
      await _createOffer();
      if (_isCancelling) {
        return;
      }

      // 计算总连接时间
      final Duration totalDuration = DateTime.now().difference(startTime);
      logI('⏱️ WebRTC总连接时间: ${totalDuration.inMilliseconds}ms');

      _isConnected = true;
      _isConnecting = false;
      _connectionStatus = 'WebRTC 已连接';
      _connectionAttempts = 0; // 连接成功后重置尝试次数
      notifyListeners();

      logI('✅ WebRTC连接建立成功');
    } catch (e) {
      if (_isCancelling) {
        logI('连接已取消');
      } else {
        // === 配置获取失败，显示错误弹窗 ===
        if (e.toString().contains('WebRTC 配置') ||
            e.toString().contains('WebRTC')) {
          _showConfigErrorDialog(e.toString());
          _isConnecting = false;
          _connectionStatus = '配置获取失败';
          notifyListeners();
          return;
        }

        // 使用智能重试算法决定是否重试
        bool shouldRetry = _shouldRetryConnection(e);

        _isConnecting = false;
        _connectionStatus = shouldRetry ? '连接失败，准备重试: $e' : '连接失败: $e';
        notifyListeners();

        logE('连接失败: $e');

        // 如果需要重试，则延迟后自动重试
        if (shouldRetry) {
          final Duration delay = _calculateRetryDelay(_connectionAttempts);
          logI('⏳ 将在 ${delay.inMilliseconds}ms 后重试...');
          await Future<void>.delayed(delay);

          // 递归调用重试连接
          if (!_isCancelling) {
            await connectToServer();
          }
        } else {
          _connectionAttempts = 0; // 重置尝试次数
        }
      }
    }
  }

  /// 预加载全局 WebRTC 配置
  Future<void> _preloadWebRtcConfig() async {
    if (_cachedWebRtcConfig == null) {
      logI('🔄 预加载全局 WebRTC 配置...');
      final config = await _webrtcConfigService.fetchWebRtcConfig();
      if (config != null) {
        _cachedWebRtcConfig = config;
        logI('✅ 全局 WebRTC 配置预加载成功');
      } else {
        logE('❌ 全局 WebRTC 配置预加载失败');
        throw Exception('无法获取 WebRTC 配置');
      }
    }
  }

  /// 显示配置错误弹窗
  void _showConfigErrorDialog(String errorMessage) {
    showDialog(
      context: _context,
      builder:
          (context) => Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 8,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.red.shade50, Colors.white],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 错误图标
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: Colors.red.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.error_outline,
                      size: 40,
                      color: Colors.red.shade700,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 标题
                  const Text(
                    '配置获取失败',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 错误信息
                  Text(
                    errorMessage,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade700,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // 提示信息
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.orange.shade200,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 16,
                          color: Colors.orange.shade700,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '请检查网络连接或联系管理员',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 确定按钮
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade600,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                      child: const Text(
                        '我知道了',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  /// 断开连接
  Future<void> disconnect() async {
    _isCancelling = true;
    logI('[系统] 🛑 正在断开连接...');
    await _cleanup();
    _isConnected = false;
    _isConnecting = false;
    _connectionStatus = '未连接';
    notifyListeners();
    logI('[系统] ✅ WebRTC 连接已断开');
  }

  /// 切换静音状态
  Future<void> toggleMute() async {
    _isMuted = !_isMuted;

    // 控制本地音频轨道的静音状态
    if (_localStream != null) {
      for (final track in _localStream!.getAudioTracks()) {
        track.enabled = !_isMuted;
      }
    }

    logI('[系统] ${_isMuted ? '🔇 已静音' : '🔊 已取消静音'}');
    notifyListeners();
  }

  /// 切换视频状态（平台路由）
  Future<void> toggleVideo() async {
    // Android平台检查：禁止启用视频功能
    if (Platform.isAndroid) {
      // 显示提示信息
      if (_context.mounted) {
        ScaffoldMessenger.of(_context).showSnackBar(
          const SnackBar(
            content: Text('安卓系统暂无法提供视频功能'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      logW('[提示] Android平台不支持视频功能');
      return;
    }

    // 平台特定处理
    if (Platform.isIOS) {
      if (_iosHandler != null) {
        await _iosHandler!.toggleVideo();
        _isVideoEnabled = _iosHandler!.isVideoEnabled;
        notifyListeners();
        return;
      }
    }

    // Fallback
    logW('[提示] Handler 未初始化');
  }

  /// 🎯 强制执行最低分辨率限制（兜底监控）
  ///
  /// 这是iOS最低分辨率限制方案的最后一道防线
  ///
  /// 仅在iOS平台生效
  Future<void> _enforceMinResolution() async {
    if (!Platform.isIOS) {
      return; // 仅iOS需要此限制
    }

    if (_peerConnection == null || !_isVideoEnabled) {
      return;
    }

    try {
      // 获取本地渲染器的当前分辨率
      if (_localRenderer.srcObject == null) {
        return;
      }

      final int currentWidth = _localRenderer.videoWidth;
      final int currentHeight = _localRenderer.videoHeight;

      // 🎯 iOS最低分辨率限制
      const int minWidth = 720;
      const int minHeight = 1280;

      if (currentWidth > 0 && currentHeight > 0) {
        // 检查是否低于最低分辨率
        if (currentWidth < minWidth || currentHeight < minHeight) {
          logW(
            '🎯 [分辨率监控] ⚠️ 分辨率低于最低限制: '
            '${currentWidth}x$currentHeight < ${minWidth}x$minHeight，'
            '尝试强制修正...',
          );

          // 获取视频发送器并强制修正
          final List<RTCRtpSender> senders =
              await _peerConnection!.getSenders();
          int fixedCount = 0;

          for (final RTCRtpSender sender in senders) {
            if (sender.track?.kind == 'video') {
              final RTCRtpParameters parameters = sender.parameters;
              final List<RTCRtpEncoding>? encodings = parameters.encodings;

              if (encodings != null && encodings.isNotEmpty) {
                final RTCRtpEncoding currentEncoding = encodings.first;

                // 强制设置 scaleResolutionDownBy ≤ 2
                final double currentScale =
                    currentEncoding.scaleResolutionDownBy ?? 1.0;
                if (currentScale > 2.0) {
                  // 创建修正后的编码参数
                  final RTCRtpEncoding fixedEncoding = RTCRtpEncoding(
                    active: currentEncoding.active,
                    maxBitrate: currentEncoding.maxBitrate,
                    scaleResolutionDownBy: 2.0, // 🎯 强制限制为2
                    maxFramerate: currentEncoding.maxFramerate,
                    rid: currentEncoding.rid,
                  );

                  // 🎯 设置 degradationPreference
                  final RTCRtpParameters fixedParams = RTCRtpParameters(
                    encodings: [fixedEncoding],
                    degradationPreference:
                        RTCDegradationPreference.MAINTAIN_RESOLUTION,
                  );

                  await sender.setParameters(fixedParams);
                  fixedCount++;

                  logI(
                    '🎯 [分辨率监控] ✅ 已强制修正: scaleResolutionDownBy $currentScale → 2.0',
                  );
                }
              }
            }
          }

          if (fixedCount > 0) {
            logI('🎯 [分辨率监控] ✅ 成功修正 $fixedCount 个视频发送器');
          } else {
            logW('🎯 [分辨率监控] ⚠️ 没有需要修正的发送器，可能需要重新连接');
          }
        } else {
          logD(
            '🎯 [分辨率监控] ✅ 分辨率正常: ${currentWidth}x$currentHeight >= ${minWidth}x$minHeight',
          );
        }
      }
    } catch (e) {
      logE('🎯 [分辨率监控] ❌ 强制执行最低分辨率失败: $e');
    }
  }

  /// 华为设备视频分辨率强制修正
  Future<void> _enforceHuaweiVideoResolution() async {
    if (_androidHandler != null) {
      await _androidHandler!.enforceVideoResolution();
    }
  }

  /// 切换前后摄像头（平台路由）
  Future<void> switchCamera() async {
    logI('🎥 [摄像头切换] ========== 切换摄像头按钮点击 ==========');
    logI('🎥 [摄像头切换] 平台: ${Platform.isAndroid ? "Android" : "iOS"}');

    if (_videoTrack == null) {
      logW('🎥 [摄像头切换] 视频轨道不存在，无法切换摄像头');
      return;
    }

    logI('🎥 [摄像头切换] 视频轨道存在: ${_videoTrack!.id}');
    logI('🎥 [摄像头切换] ======================================');

    try {
      // 平台特定处理
      bool success = false;

      if (Platform.isAndroid) {
        logI('🎥 [摄像头切换] 使用 Android Handler');
        // Android 使用专用 Handler
        if (_androidHandler != null) {
          logI('🎥 [摄像头切换] Android Handler 已初始化');
          success = await _androidHandler!.switchCamera();
        } else {
          logE('🎥 [摄像头切换] Android Handler 未初始化');
        }
      } else if (Platform.isIOS) {
        logI('🎥 [摄像头切换] 使用 iOS Handler');
        // iOS 使用专用 Handler
        if (_iosHandler != null) {
          logI('🎥 [摄像头切换] iOS Handler 已初始化');
          success = await _iosHandler!.switchCamera();
        } else {
          logE('🎥 [摄像头切换] iOS Handler 未初始化');
        }
      } else {
        logW('🎥 [摄像头切换] 使用 fallback 方式');
        // Fallback：使用 flutter_webrtc 的 Helper.switchCamera
        logW('[提示] 使用 fallback 方式切换摄像头');
        success = await Helper.switchCamera(_videoTrack!);
      }

      logI('🎥 [摄像头切换] 切换结果: ${success ? "成功" : "失败"}');
      logI('🎥 [摄像头切换] ======================================');

      if (success) {
        logI('[系统] 🎥 摄像头已切换');
        notifyListeners();
      } else {
        logW('[警告] 摄像头切换失败');
      }
    } catch (e) {
      logE('[错误] 摄像头切换异常: $e');
    }
  }

  /// 配置音频会话（解决iOS音量小的问题，增强Android音量）
  ///
  /// 🔑 关键修复（第三轮）：自定义 Android 音频配置
  ///
  /// **问题分析**：
  /// 1. `RTCVideoRenderer.setVolume()` 在 Android 上对**远程流不工作**（flutter_webrtc bug #870）
  /// 2. WebRTC Android 默认使用 `STREAM_VOICE_CALL`，该流有系统级别的音量限制
  /// 3. `MODE_IN_COMMUNICATION` 模式会进一步限制音量上限
  /// 4. `AndroidAudioConfiguration.media` 预设可能没有明确设置 `androidAudioStreamType`
  ///
  /// **解决方案**：
  /// - 创建自定义配置，明确设置 `androidAudioStreamType: AndroidAudioStreamType.music`
  /// - 设置 `androidAudioMode: AndroidAudioMode.normal`（而非 `inCommunication`）
  /// - `STREAM_MUSIC` 没有音量上限限制，可以获得最大音量
  ///
  /// **注意事项**：
  /// - 此配置必须在 WebRTC 会话开始前设置，无法在会话中更改
  /// - 移除了 `setSpeakerphoneOn` 调用，因为该调用会覆盖上述配置
  Future<void> _configureAudioSession() async {
    try {
      logI('[系统] 🔧 开始配置音频会话...');

      if (Platform.isIOS) {
        // 配置iOS音频会话模式
        // 使用 playAndRecord 模式，支持播放和录制，并强制使用扬声器
        await Helper.setAppleAudioIOMode(
          AppleAudioIOMode.localAndRemote,
          preferSpeakerOutput: true,
        );
        logI('[系统] ✅ iOS音频会话已配置为播放录制模式，强制使用扬声器');

        // iOS 需要此调用确保扬声器启用
        await Helper.setSpeakerphoneOn(true);
        logI('[系统] 🔊 iOS扬声器已启用');
      } else if (Platform.isAndroid) {
        // 🔑 关键修复（第三轮）：使用自定义配置，强制使用 STREAM_MUSIC 而非 STREAM_VOICE_CALL
        //
        // 问题分析：
        // - WebRTC Android 默认使用 STREAM_VOICE_CALL，该流有系统音量限制
        // - RTCVideoRenderer.setVolume() 在 Android 上对远程流不工作（flutter_webrtc 已知 bug）
        // - AndroidAudioConfiguration.media 预设可能没有明确设置 streamType
        //
        // 解决方案：
        // - 明确设置 androidAudioStreamType 为 music（STREAM_MUSIC）
        // - 明确设置 androidAudioMode 为 normal（MODE_NORMAL）
        // - STREAM_MUSIC 没有音量上限限制，可以获得最大音量
        //
        // ⚠️ 注意：此配置必须在 WebRTC 会话开始前设置，无法在会话中更改
        await Helper.setAndroidAudioConfiguration(
          AndroidAudioConfiguration(
            // 使用 NORMAL 模式，而非 IN_COMMUNICATION 模式（限制音量）
            androidAudioMode: AndroidAudioMode.normal,
            // 🎯 关键：使用 MUSIC 流类型，而非 VOICE_CALL（有音量限制）
            androidAudioStreamType: AndroidAudioStreamType.music,
            // 使用媒体用途类型
            androidAudioAttributesUsageType: AndroidAudioAttributesUsageType.media,
            // 让 flutter_webrtc 自动管理音频焦点
            manageAudioFocus: true,
            // 强制处理音频路由（确保使用扬声器）
            forceHandleAudioRouting: true,
          ),
        );
        logI('[系统] ✅ Android音频配置已自定义：MODE_NORMAL + STREAM_MUSIC（最大音量）');
        logI('[系统] 📊 配置详情: mode=normal, streamType=music, usageType=media');
      }
    } catch (e) {
      logW('[警告] ⚠️ 音频会话配置失败: $e');
      logI('[提示] 继续使用默认音频配置，可能影响音量');
      logE('音频会话配置失败: $e');
    }
  }

  // 初始化状态标记
  bool _isRenderersInitialized = false;
  bool _isInitializing = false;

  /// 初始化方法
  Future<void> initialize() async {
    if (_isInitializing || _isDisposed) {
      return;
    }

    _isInitializing = true;

    try {
      if (!_isRenderersInitialized) {
        await _initializeRenderers();
        if (_isDisposed) {
          return;
        }
        _isRenderersInitialized = true;
      }

      await _requestPermissions();
      if (_isDisposed) {
        return;
      }

      // 外部 WebSocket 由 chat 页面管理，不再在此处连接
    } finally {
      _isInitializing = false;
    }
  }

  /// 创建WebRTC PeerConnection
  Future<void> _createPeerConnection() async {
    // 获取配置（现在是从后端全局配置动态获取）
    final Map<String, dynamic> configuration = await createRtcConfiguration();

    _peerConnection = await createPeerConnection(configuration);

    // 重置 ICE 相关状态
    _iceCandidateCount = 0;
    _iceGatheringCompleter = Completer<void>();

    // 监听ICE候选 - 技术日志只输出到控制台
    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      _iceCandidateCount++;
      // 🔧 优化：格式化ICE候选日志，只显示关键信息
      if (candidate.candidate != null) {
        final String formattedCandidate = _formatIceCandidate(
          candidate.candidate!,
        );
        logD('🧊 ICE候选 #$_iceCandidateCount: $formattedCandidate');
      }
      _pendingIceCandidates.add(candidate);

      // 注意：在flutter_webrtc中，candidate.candidate为null表示ICE收集完成
      if (candidate.candidate == null) {
        logI('✅ ICE 候选收集完成，总计: $_iceCandidateCount 个');
        _isIceGatheringComplete = true;

        // 🔧 优化：立即完成ICE收集，不再等待超时
        if (!_iceGatheringCompleter!.isCompleted) {
          _iceGatheringCompleter!.complete();
        }

        // 确保最后的候选也被发送
        if (_pendingIceCandidates.isNotEmpty) {
          _sendPendingIceCandidates();
        }
      } else {
        // 🔧 新增：收到一定数量候选后，检查是否可以提前完成收集
        if (_iceCandidateCount >= 10 && !_isIceGatheringComplete) {
          logD('🔍 已收集$_iceCandidateCount个候选，检查是否可以完成ICE收集...');

          // 延迟500ms后检查是否还有新候选，如果没有则提前完成
          Future<void>.delayed(const Duration(milliseconds: 500), () {
            if (!_isIceGatheringComplete &&
                _iceGatheringCompleter != null &&
                !_iceGatheringCompleter!.isCompleted) {
              logI('🚀 ICE收集活跃度降低，提前完成收集（已有$_iceCandidateCount个候选）');
              _isIceGatheringComplete = true;
              _iceGatheringCompleter!.complete();

              if (_pendingIceCandidates.isNotEmpty) {
                _sendPendingIceCandidates();
              }
            }
          });
        }
      }
    };

    // 监听 ICE 收集状态变化 - 技术日志只输出到控制台
    _peerConnection!.onIceGatheringState = (RTCIceGatheringState state) {
      logD('🧊 ICE 收集状态: $state');
      // 🔧 优化：ICE收集状态完成时，避免重复完成
      if (state == RTCIceGatheringState.RTCIceGatheringStateComplete) {
        _isIceGatheringComplete = true;
        if (_iceGatheringCompleter != null &&
            !_iceGatheringCompleter!.isCompleted) {
          _iceGatheringCompleter!.complete();
        }
        logI('✅ ICE 收集状态完成，触发收集完成');
      }
    };

    // 监听远程流
    _peerConnection!.onTrack = (RTCTrackEvent event) async {
      logI('🎯 [onTrack] 事件触发，时间: ${DateTime.now().millisecondsSinceEpoch}');

      if (event.streams.isNotEmpty) {
        final newStream = event.streams[0];
        logI(
          '🎯 [onTrack] 新流信息: ID=${newStream.id}, 轨道数=${newStream.getAudioTracks().length}',
        );

        // 记录旧流信息用于对比
        final String? oldStreamId = _remoteStream?.id;

        _remoteStream = newStream;

        logI('🎯 [onTrack] 流变化: $oldStreamId → ${newStream.id}');

        // 统一处理音频和视频轨道
        _handleMediaTracks(newStream.getAudioTracks(), '音频');
        _handleMediaTracks(newStream.getVideoTracks(), '视频');

        _remoteRenderer.srcObject = _remoteStream;

        // 🔧 Android 音量增强方案：使用 setVolume 方法提升远程音频音量
        // 注意：setVolume 是异步方法，需要 await
        if (Platform.isAndroid) {
          await _remoteRenderer.setVolume(2.0);
          logI('[系统] 🔊 Android远程音频音量已增强为 2.0 倍');
        } else {
          await _remoteRenderer.setVolume(1.0);
          logI('[系统] 🔊 iOS远程渲染器已设置');
        }

        // 设置接收音频状态，用于波形动画
        _isReceivingAudio = true;
        notifyListeners();

        // 3秒后重置接收音频状态（模拟音频播放结束）
        Future.delayed(const Duration(seconds: 3), () {
          _isReceivingAudio = false;
          notifyListeners();
        });
      }
    };

    // 监听连接状态变化 - 重要状态变化输出到控制台
    _peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
      logI(
        '🔄 [connectionState] WebRTC连接状态变化: $state, 时间: ${DateTime.now().millisecondsSinceEpoch}',
      );

      switch (state) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          _connectionStatus = 'WebRTC 已连接';
          logI('✅ [connectionState] WebRTC连接已建立，远程流: ${_remoteStream?.id}');

          // 🎥 连接建立后，检查本地视频轨道状态
          _startLocalVideoTrackMonitoring();

          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
          _connectionStatus = 'WebRTC 连接中...';
          logD('🔄 [connectionState] WebRTC连接中...');
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
          _connectionStatus = 'WebRTC 已断开';
          logI('⚠️ [connectionState] WebRTC连接已断开，远程流: ${_remoteStream?.id}');
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          _connectionStatus = 'WebRTC 连接失败';
          logE('❌ [connectionState] WebRTC连接失败');
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
          _connectionStatus = 'WebRTC 已关闭';
          logD('🔒 [connectionState] WebRTC连接已关闭');
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateNew:
          _connectionStatus = 'WebRTC 新建连接';
          logD('🆕 [connectionState] WebRTC新建连接');
          break;
      }

      notifyListeners();
    };

    // 监听ICE连接状态
    _peerConnection!.onIceConnectionState = (RTCIceConnectionState state) {
      String stateStr = '';
      switch (state) {
        case RTCIceConnectionState.RTCIceConnectionStateNew:
          stateStr = 'ICE新建';
          break;
        case RTCIceConnectionState.RTCIceConnectionStateChecking:
          stateStr = 'ICE检查中';
          break;
        case RTCIceConnectionState.RTCIceConnectionStateConnected:
          stateStr = 'ICE已连接';
          logI('🎉 ICE连接成功，音频传输通道已建立');
          break;
        case RTCIceConnectionState.RTCIceConnectionStateCompleted:
          stateStr = 'ICE连接完成';
          logI('✅ ICE连接完成');
          break;
        case RTCIceConnectionState.RTCIceConnectionStateFailed:
          stateStr = 'ICE连接失败';
          logE('❌ ICE连接失败，音频传输可能有问题');
          break;
        case RTCIceConnectionState.RTCIceConnectionStateDisconnected:
          stateStr = 'ICE连接断开';
          logW('⚠️ ICE连接断开');
          break;
        case RTCIceConnectionState.RTCIceConnectionStateClosed:
          stateStr = 'ICE连接关闭';
          logD('🔒 ICE连接关闭');
          break;
        default:
          stateStr = 'ICE状态未知: $state';
          logW(stateStr);
          break;
      }
    };

    // 监听数据通道状态
    _peerConnection!.onDataChannel = (RTCDataChannel dataChannel) {
      _dataChannel = dataChannel;
      dataChannel.onMessage = (RTCDataChannelMessage message) {
        logD('[数据通道] ${message.text}');
      };

      logI('[系统] 数据通道已建立');
    };
  }

  /// 获取用户媒体（音频）
  Future<void> _getUserMedia() async {
    _audioStatus = '正在获取音频流...';
    _lastAudioError = '';
    notifyListeners();

    try {
      // 检查麦克风权限
      if (!_hasMicrophonePermission) {
        throw Exception('麦克风权限未授予');
      }

      logI('[系统] 正在请求音视频流...');

      // 获取音视频流（iOS：音视频，Android：仅音频）
      // 🔧 平台特定视频约束：iOS 和 Android 使用不同的约束格式
      // 🔑 Android 平台暂不请求视频流传输，仅传输音频
      final Map<String, dynamic> constraints = <String, dynamic>{
        'audio': <String, dynamic>{
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
          'sampleRate': 16000,
          'channelCount': 1,
          // 🔧 Android 音量增强：增加音频增益配置
          // 注意：部分浏览器/设备可能不支持此参数
          ...Platform.isAndroid ? {'gain': 2.0} : {},
        },
        // 🔑 Android: 完全不请求视频流（仅音频模式）
        // iOS: 请求视频流（支持视频功能）
        ...Platform.isIOS ? {
          'video': <String, dynamic>{
            // 🔑 iOS WebRTC 约束格式：使用字符串值和 width/height/facingMode 顶层属性
            // 🎯 iOS最低分辨率限制方案：
            // - iOS摄像头支持的分辨率：1920x1080(FHD), 1280x720(HD), 640x480(VGA)
            // - 要求最低720x1280 (HD竖屏)，优先1920x1080 (FHD竖屏)
            'width': <String, dynamic>{
              'min': '720', // 🎯 最低宽度 720 (HD)
              'ideal': '1080', // 理想宽度 1080 (FHD)
              'max': '1080', // 最大宽度 1080
            },
            'height': <String, dynamic>{
              'min': '1280', // 🎯 最低高度 1280 (HD竖屏)
              'ideal': '1920', // 理想高度 1920 (FHD)
              'max': '1920', // 最大高度 1920
            },
            'frameRate': <String, dynamic>{
              'min': '15', // 最低帧率 15fps
              'ideal': '30', // 理想帧率 30fps
              'max': '30', // 最大帧率 30fps
            },
            'facingMode': 'environment', // 后置摄像头
          },
        } : {},
      };

      // 记录平台特定的视频约束
      if (Platform.isIOS) {
        logI('[系统] 📱 [iOS] 使用iOS视频约束：最低720x1280，理想1080x1920');
      } else if (Platform.isAndroid) {
        logI('[系统] 🤖 [Android] 使用Android视频约束：仅音频，不请求视频');
      }

      final MediaStream stream = await navigator.mediaDevices.getUserMedia(
        constraints,
      );

      // 检查音频流
      final List<MediaStreamTrack> audioTracks = stream.getAudioTracks();
      if (audioTracks.isEmpty) {
        throw Exception('未找到音频轨道');
      }

      final MediaStreamTrack audioTrack = audioTracks.first;
      logI('[系统] 音频流获取成功: ${audioTrack.label}');

      // 获取视频轨道引用（仅 iOS）
      // Android 平台不获取视频流，所以 videoTracks 可能为空
      final List<MediaStreamTrack> videoTracks = stream.getVideoTracks();

      if (Platform.isIOS) {
        // iOS 要求必须有视频轨道
        if (videoTracks.isEmpty) {
          throw Exception('未找到视频轨道');
        }
        _videoTrack = videoTracks.first;
        _videoTrack!.enabled = false;
        _isVideoEnabled = false;
        logI('📹 [摄像头诊断] [iOS] 视频轨道已禁用: ${_videoTrack!.label}');
      } else {
        // Android: 不使用视频轨道
        _videoTrack = null;
        _isVideoEnabled = false;
        logI('📹 [摄像头诊断] [Android] 跳过视频轨道（仅音频模式）');
      }

      // 📹 新增：详细的视频轨道诊断日志（仅 iOS）
      if (Platform.isIOS && _videoTrack != null) {
        logI('📹 [摄像头诊断] ========== 视频轨道详细信息 ==========');
        logI('📹 [摄像头诊断] 轨道ID: ${_videoTrack!.id}');
        logI('📹 [摄像头诊断] 轨道标签: ${_videoTrack!.label}');
        logI('📹 [摄像头诊断] 轨道类型: ${_videoTrack!.kind}');
        logI('📹 [摄像头诊断] 轨道启用状态: ${_videoTrack!.enabled}');
        logI('📹 [摄像头诊断] 轨道静音状态: ${_videoTrack!.muted}');
        logI('📹 [摄像头诊断] 设备平台: iOS');
        logI('📹 [摄像头诊断] 设备制造商: ${await _getDeviceManufacturer()}');

        // 尝试获取摄像头朝向信息
        try {
          final settings = _videoTrack!.getSettings();
          logI('📹 [摄像头诊断] 摄像头设置: $settings');

          final facingMode = settings['facingMode'];
          logI('📹 [摄像头诊断] 摄像头朝向 (facingMode): $facingMode');

          if (facingMode != 'environment') {
            logW('📹 [摄像头诊断] ⚠️ 警告: 摄像头朝向不是后置(environment), 实际: $facingMode');
          }
        } catch (e) {
          logW('📹 [摄像头诊断] 无法获取摄像头设置: $e');
        }

        // 获取约束信息
        try {
          final constraints = _videoTrack!.getConstraints();
          logI('📹 [摄像头诊断] 摄像头约束: $constraints');
        } catch (e) {
          logW('📹 [摄像头诊断] 无法获取摄像头约束: $e');
        }

        logI('📹 [摄像头诊断] ========================================');
      }


      // 监听音频轨道状态
      audioTrack.onEnded = () {
        _isRecording = false;
        _audioStatus = '音频流已结束';
        notifyListeners();
        logI('[系统] 音频流已结束');
      };

      audioTrack.onMute = () {
        _isRecording = false;
        _audioStatus = '音频已静音';
        notifyListeners();
        logI('[系统] 音频已静音');
      };

      // onUnmute 在 flutter_webrtc 中可能不支持，我们用其他方式监控
      if (audioTrack.enabled) {
        _isRecording = true;
        _audioStatus = '音频正常录制中';
        notifyListeners();
        logI('[系统] 音频恢复正常录制');
      }

      _localStream = stream;
      _isRecording = true;
      _audioStatus = '音频流已建立，正在录制';
      notifyListeners();

      // 将轨道添加到PeerConnection - 使用 addTransceiver 方式配置编码参数
      for (final MediaStreamTrack track in _localStream!.getTracks()) {
        if (track.kind == 'audio') {
          // 音频轨道使用 addTrack（简单方式）
          await _peerConnection!.addTrack(track, _localStream!);
          logI(
            '[系统] AUDIO轨道已添加到WebRTC连接: ${track.label}, enabled=${track.enabled}',
          );
        } else if (track.kind == 'video' && Platform.isIOS) {
          // 🔑 仅 iOS 添加视频轨道
          // Android 不进入此分支（因为 _localStream 没有视频轨道）
          logI('[系统] 正在添加 VIDEO 轨道到 Transceiver，配置编码参数...');

          final RTCRtpTransceiverInit transceiverInit = IOSWebRTCHandler.getTransceiverInit();

          // 创建 iOS Handler
          _iosHandler = IOSWebRTCHandler(
            peerConnection: _peerConnection,
            localStream: _localStream,
            localRenderer: _localRenderer,
          );
          _iosHandler!.setVideoTrack(track);

          final RTCRtpTransceiver transceiver = await _peerConnection!
              .addTransceiver(track: track, init: transceiverInit);

          logI(
            '[系统] VIDEO轨道已添加到 Transceiver (iOS), degradationPreference=MAINTAIN_RESOLUTION',
          );

          // iOS 保持原有 degradationPreference 设置
          try {
            final sender = transceiver.sender;
            final parameters = sender.parameters;

            final updatedParameters = RTCRtpParameters(
              encodings: parameters.encodings,
              degradationPreference:
                  RTCDegradationPreference.MAINTAIN_RESOLUTION,
            );

            await sender.setParameters(updatedParameters);
            logI('[系统] degradationPreference 已设置为 MAINTAIN_RESOLUTION');
          } catch (e) {
            logW('[警告] 设置 degradationPreference 失败: $e');
          }
        }
      }

      // 设置本地视频渲染器（仅 iOS）
      // Android 不使用视频功能，跳过渲染器初始化
      if (_videoTrack != null && Platform.isIOS) {
        logI('🎨 [渲染器初始化] 开始设置本地视频渲染器...');

        // 📹 修复：增加延迟，等待摄像头完全初始化（华为白屏修复）
        final initDelay = Platform.isAndroid ? 500 : 100;
        logI('🎨 [渲染器初始化] 等待 $initDelay ms 以确保摄像头完全初始化...');
        await Future.delayed(Duration(milliseconds: initDelay));

        _localRenderer.srcObject = _localStream;
        logI('🎨 [渲染器初始化] 媒体流已绑定到渲染器');

        await Future.delayed(Duration(milliseconds: initDelay));

        final int width = _localRenderer.videoWidth;
        final int height = _localRenderer.videoHeight;

        // 📹 详细的渲染器诊断日志
        logI('🎨 [渲染器诊断] ========== 渲染器详细信息 ==========');
        logI('🎨 [渲染器诊断] 渲染器宽度: $width');
        logI('🎨 [渲染器诊断] 渲染器高度: $height');
        if (width > 0 && height > 0) {
          logI('🎨 [渲染器诊断] 宽高比: ${(width / height).toStringAsFixed(2)}');
        }

        if (width > 0 && height > 0) {
          logI('🎨 [渲染器诊断] ✅ 渲染器分辨率正常: ${width}x$height');
          if (width < 480 || height < 640) {
            logW('🎨 [渲染器诊断] ⚠️ 渲染器分辨率低于最低预期');
          }
        } else {
          logE('🎨 [渲染器诊断] ❌ 渲染器分辨率异常: ${width}x$height');

          // 尝试重新绑定渲染器
          logI('🎨 [渲染器诊断] 尝试重新绑定渲染器...');
          _localRenderer.srcObject = null;
          await Future.delayed(Duration(milliseconds: 200));
          _localRenderer.srcObject = _localStream;
          await Future.delayed(Duration(milliseconds: 200));

          final int newWidth = _localRenderer.videoWidth;
          final int newHeight = _localRenderer.videoHeight;
          logI('🎨 [渲染器诊断] 重新绑定后分辨率: ${newWidth}x$newHeight');
        }

        logI('🎨 [渲染器诊断] ========================================');

        logI(
          '[系统] 本地视频渲染器已设置（${_isVideoEnabled ? "视频已启用" : "视频默认禁用"}）: '
          '${width}x$height',
        );

        // 验证分辨率
        if (width < 1920 || height < 1080) {
          logW(
            '[警告] ⚠️ 渲染器分辨率低于预期: ${width}x$height，'
            '预期: 1920x1080',
          );
        }
      }

      // 等待一小段时间确保轨道添加完成
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // 主动创建数据通道（重要！）
      await _createDataChannel();

      // 启动音频级别监控
      _startAudioLevelMonitoring();
    } catch (e) {
      _isRecording = false;
      _audioStatus = '音频流获取失败';
      _lastAudioError = e.toString();
      notifyListeners();
      logE('[错误] 获取音频失败: $e');
      throw Exception('获取音频失败: $e');
    }
  }

  /// 创建数据通道
  Future<void> _createDataChannel() async {
    try {
      final RTCDataChannel dataChannel = await _peerConnection!
          .createDataChannel('audio_data', RTCDataChannelInit());

      _dataChannel = dataChannel;

      dataChannel.onMessage = (RTCDataChannelMessage message) {
        logD('[数据通道接收] ${message.text}');
      };

      logI('[系统] 数据通道创建成功');
    } catch (e) {
      logE('[错误] 创建数据通道失败: $e');
      throw Exception('创建数据通道失败: $e');
    }
  }

  /// 创建WebRTC Offer
  Future<void> _createOffer() async {
    try {
      final RTCSessionDescription offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);

      // 等待ICE收集完成
      await _waitForIceGatheringComplete();
      logI('[系统] ✅ ICE 候选收集完成，开始发送 Offer');

      // 发送offer到服务器
      await _sendOfferToServer(offer);
    } catch (e) {
      throw Exception('创建Offer失败: $e');
    }
  }

  /// 等待ICE收集完成
  Future<void> _waitForIceGatheringComplete() async {
    if (_isIceGatheringComplete) {
      return;
    }

    // 设置超时保护，防止无限等待
    const Duration timeout = Duration(milliseconds: 300);

    try {
      await _iceGatheringCompleter!.future.timeout(timeout);
      logI('[系统] ✅ ICE收集完成 (收集了$_iceCandidateCount个候选)');
    } on TimeoutException {
      logW('[警告] ⚠️ ICE收集超时，但继续发送Offer (已有$_iceCandidateCount个候选)');
      // 超时后不抛出异常，继续流程
    } catch (e) {
      logE('[错误] ❌ ICE收集等待异常: $e');
      rethrow;
    }
  }

  /// 发送Offer到服务器 - 使用统一的session_id
  Future<void> _sendOfferToServer(RTCSessionDescription offer) async {
    try {
      // 验证session_id
      if (_sessionId == null || _sessionId!.isEmpty) {
        throw Exception('session_id无效，无法发送Offer');
      }

      // 检查是否为重复请求
      if (_isDuplicateOffer(_sessionId!)) {
        logW('[警告] ⚠️ 检测到重复的Offer请求，跳过发送');
        return;
      }

      _lastOfferSent = _sessionId;
      logI('[系统] 📤 发送 Offer 到服务器...');
      logD('[调试] 📋 Offer SDP 长度: ${offer.sdp?.length ?? 0} 字符');
      logD('[调试] 📋 Offer 类型: ${offer.type}');
      logD('[调试] 📋 Session ID: $_sessionId');

      final HttpClient httpClient = HttpClient();

      // 在开发环境中忽略SSL证书错误
      httpClient.badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;

      logI('[系统] 🌐 连接服务器: $serverUrl/webrtc/offer');
      final HttpClientRequest response = await httpClient.postUrl(
        Uri.parse('$serverUrl/webrtc/offer'),
      );

      response.headers.contentType = ContentType.json;

      final String body = json.encode(<String, dynamic>{
        'sdp': offer.sdp,
        'type': offer.type,
        'webrtc_id': _sessionId, // 确保使用与WebSocket相同的session_id
      });

      logD('[调试] 📤 发送请求体大小: ${body.length} 字符');
      response.write(body);

      logI('[系统] ⏳ 等待服务器响应...');
      final HttpClientResponse httpResponse = await response.close();

      logI('[系统] 📨 收到服务器响应，状态码: ${httpResponse.statusCode}');

      if (httpResponse.statusCode == 200) {
        final String responseData =
            await httpResponse.transform(utf8.decoder).join();
        logD('[调试] 📨 响应数据长度: ${responseData.length} 字符');

        final Map<String, dynamic> serverResponse = json.decode(responseData);
        logD('[调试] 📋 服务器响应类型: ${serverResponse['type'] ?? 'unknown'}');
        logD('[调试] 📋 服务器响应 SDP 长度: ${serverResponse['sdp']?.length ?? 0} 字符');

        // 设置远程描述
        final RTCSessionDescription answer = RTCSessionDescription(
          serverResponse['sdp'],
          serverResponse['type'],
        );

        logI('[系统] 📡 设置远程描述...');
        await _peerConnection!.setRemoteDescription(answer);
        logI('[系统] ✅ WebRTC协商完成');
      } else {
        final String errorResponse =
            await httpResponse.transform(utf8.decoder).join();
        logE('[错误] ❌ 服务器响应错误: ${httpResponse.statusCode}');
        logD('[调试] 错误详情: $errorResponse');
        throw Exception('服务器响应错误: ${httpResponse.statusCode}');
      }

      httpClient.close();
    } on SocketException catch (e) {
      logE('[网络错误] ❌ 网络连接失败: $e');
      throw Exception('网络连接失败: $e');
    } on TimeoutException catch (e) {
      logE('[网络错误] ❌ 请求超时: $e');
      throw Exception('请求超时: $e');
    } catch (e) {
      logE('[错误] ❌ 发送Offer失败: $e');
      throw Exception('发送Offer失败: $e');
    }
  }

  /// 发送待处理的ICE候选 - 使用统一的session_id
  Future<void> _sendPendingIceCandidates() async {
    if (_pendingIceCandidates.isEmpty || _isCancelling) {
      return;
    }

    // 验证session_id
    if (_sessionId == null || _sessionId!.isEmpty) {
      logE('❌ session_id无效，无法发送ICE候选');
      return;
    }

    logI('📤 批量发送 ${_pendingIceCandidates.length} 个 ICE 候选到服务器...');

    final List<RTCIceCandidate> candidates = List<RTCIceCandidate>.from(
      _pendingIceCandidates,
    );
    _pendingIceCandidates.clear();
    _iceCandidateBatchTimer?.cancel();
    _iceCandidateBatchTimer = null;

    try {
      final HttpClient httpClient = HttpClient();
      httpClient.badCertificateCallback = (
        X509Certificate cert,
        String host,
        int port,
      ) {
        return true;
      };

      for (final RTCIceCandidate candidate in candidates) {
        if (_isCancelling) {
          break;
        }

        final HttpClientRequest response = await httpClient.postUrl(
          Uri.parse('$serverUrl/webrtc/offer'),
        );

        response.headers.contentType = ContentType.json;

        final String body = json.encode(<String, dynamic>{
          'candidate': candidate.toMap(),
          'webrtc_id': _sessionId, // 确保使用与WebSocket相同的session_id
          'type': 'ice-candidate',
        });

        response.write(body);
        await response.close();

        // 添加小延迟避免过快发送
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      logI('✅ 批量 ICE 候选发送成功 (${candidates.length} 个)');
      httpClient.close();
    } catch (e) {
      logE('❌ 批量发送ICE候选失败: $e');
      // ICE 候选发送失败不应该中断整个连接流程
    }
  }

  /// 启动音频级别监控
  void _startAudioLevelMonitoring() {
    _audioLevelTimer?.cancel();
    _audioLevelTimer = Timer.periodic(const Duration(seconds: 1), (
      Timer timer,
    ) {
      if (_localStream != null && _isRecording) {
        final List<MediaStreamTrack> audioTracks =
            _localStream!.getAudioTracks();
        if (audioTracks.isNotEmpty) {
          final MediaStreamTrack track = audioTracks.first;
          if (track.enabled) {
            _audioFrameCount++;
            _audioStatus = '音频正常录制中 (帧数: $_audioFrameCount)';

            // 每10帧发送一次状态检查消息
            if (_audioFrameCount % 10 == 0) {
              logD('[音频监控] 已录制 $_audioFrameCount 帧，ICE状态: $_connectionStatus');
            }
          } else {
            _audioStatus = '音频已禁用';
          }
          notifyListeners();
        }
      }
    });

    // 启动媒体统计监控（包含音频和视频）
    _startMediaStatsMonitoring();
  }

  /// 启动媒体统计监控（音频和视频）
  void _startMediaStatsMonitoring() {
    _audioStatsTimer?.cancel();
    _audioStatsTimer = Timer.periodic(const Duration(seconds: 5), (
      Timer timer,
    ) {
      if (_peerConnection != null) {
        _checkMediaTransmission();
      }
    });
  }

  /// 统一处理媒体轨道（音频/视频），监控所有轨道状态
  void _handleMediaTracks(List<MediaStreamTrack> tracks, String trackType) {
    for (final MediaStreamTrack track in tracks) {
      logI(
        '[onTrack] $trackType轨道: ID=${track.label}, enabled=${track.enabled}, muted=${track.muted}',
      );

      // 监听轨道状态变化
      track.onEnded = () {
        logI('[$trackType] 轨道已结束: ${track.label}');
      };
      track.onMute = () {
        logI('[$trackType] 轨道已静音: ${track.label}');
      };
    }
  }

  /// 🎥 启动本地视频轨道监控 - 验证视频是否实际传输
  void _startLocalVideoTrackMonitoring() {
    logI('🎥 [视频监控] 开始监控本地视频轨道传输状态...');

    // 立即执行一次检查
    _checkLocalVideoTrackTransmission();

    // 🎯 iOS最低分辨率监控：立即执行一次最低分辨率检查
    if (Platform.isIOS && _isVideoEnabled) {
      _enforceMinResolution();
    }

    // 🔑 新增：华为设备分辨率修正
    if (Platform.isAndroid && _isVideoEnabled) {
      _enforceHuaweiVideoResolution();
    }

    // 设置定时监控，每2秒检查一次
    Timer.periodic(const Duration(seconds: 2), (Timer timer) {
      // 如果连接断开或关闭，停止监控
      if (_connectionStatus != 'WebRTC 已连接') {
        timer.cancel();
        logI('🎥 [视频监控] 连接已断开，停止监控');
        return;
      }

      _checkLocalVideoTrackTransmission();

      // 🎯 iOS最低分辨率监控：定时执行最低分辨率检查
      if (Platform.isIOS && _isVideoEnabled) {
        _enforceMinResolution();
      }

      // 🔑 新增：华为设备分辨率修正（定时检查）
      if (Platform.isAndroid && _isVideoEnabled) {
        _enforceHuaweiVideoResolution();
      }
    });
  }

  /// 🎥 检查本地视频轨道传输状态
  Future<void> _checkLocalVideoTrackTransmission() async {
    try {
      // 检查本地流是否存在
      if (_localStream == null) {
        logW('🎥 [视频监控] ⚠️ 本地媒体流为空');
        return;
      }

      // 获取视频轨道
      final List<MediaStreamTrack> videoTracks = _localStream!.getVideoTracks();
      if (videoTracks.isEmpty) {
        logW('🎥 [视频监控] ⚠️ 本地视频轨道列表为空');
        return;
      }

      final MediaStreamTrack videoTrack = videoTracks.first;

      // 检查视频轨道状态
      logI(
        '🎥 [视频监控] 视频轨道状态: '
        'enabled=${videoTrack.enabled}, '
        'muted=${videoTrack.muted}, '
        'label="${videoTrack.label}", '
        'id="${videoTrack.id}"',
      );

      // 检查本地视频渲染器状态
      if (_localRenderer.srcObject != null) {
        final int videoWidth = _localRenderer.videoWidth;
        final int videoHeight = _localRenderer.videoHeight;

        if (videoWidth > 0 && videoHeight > 0) {
          logI('🎥 [视频监控] ✅ 本地视频渲染器正常: ${videoWidth}x$videoHeight');

          // 检查是否有实际的视频数据在传输
          // 通过检查videoTrack的enabled状态来判断
          final bool enabled = videoTrack.enabled;
          final bool muted = videoTrack.muted ?? false;
          if (!enabled) {
            logW('🎥 [视频监控] ⚠️ 视频轨道已禁用或状态未知，可能无法传输视频数据');
          } else if (muted) {
            logW('🎥 [视频监控] ⚠️ 视频轨道已静音，可能无法传输视频数据');
          } else {
            logI('🎥 [视频监控] ✅ 视频轨道状态正常，应该正在传输视频数据');
          }
        } else {
          logW('🎥 [视频监控] ⚠️ 本地视频渲染器未就绪: ${videoWidth}x$videoHeight');
          logW('🎥 [视频监控] ⚠️ 这可能表示本地摄像头未正常启动或视频轨道未激活');
        }
      } else {
        logW('🎥 [视频监控] ⚠️ 本地视频渲染器srcObject为空，视频未绑定到渲染器');
      }
    } catch (e) {
      logE('🎥 [视频监控] ❌ 检查本地视频轨道传输状态时出错: $e');
    }
  }

  /// 检查媒体传输状态（音频和视频）
  void _checkMediaTransmission() {
    logI('🔍 [媒体传输检查] 开始检查，时间: ${DateTime.now().millisecondsSinceEpoch}');

    // ========== 检查本地音频轨道 ==========
    if (_localStream != null) {
      final List<MediaStreamTrack> audioTracks = _localStream!.getAudioTracks();
      if (audioTracks.isNotEmpty) {
        final MediaStreamTrack track = audioTracks.first;
        logI(
          '[媒体传输检查] 音频: enabled=${track.enabled}, muted=${track.muted}, label=${track.label}',
        );
      } else {
        logW('[媒体传输检查] 警告: 本地音频轨道为空');
      }
    } else {
      logW('[媒体传输检查] 警告: 本地媒体流为空');
    }

    // ========== 检查本地视频轨道 ==========
    if (_localStream != null) {
      final List<MediaStreamTrack> videoTracks = _localStream!.getVideoTracks();
      if (videoTracks.isNotEmpty) {
        final MediaStreamTrack track = videoTracks.first;
        logI(
          '[媒体传输检查] 本地视频轨道: enabled=${track.enabled}, muted=${track.muted}, label=${track.label}',
        );
      } else {
        logW('[媒体传输检查] 警告: 本地视频轨道为空');
      }

      // 检查本地视频渲染器状态
      if (_localRenderer.srcObject != null) {
        final int videoWidth = _localRenderer.videoWidth;
        final int videoHeight = _localRenderer.videoHeight;
        if (videoWidth > 0 && videoHeight > 0) {
          logI('[媒体传输检查] 本地视频渲染器: ${videoWidth}x$videoHeight');
        } else {
          logW('[媒体传输检查] 警告: 本地视频渲染器未就绪');
        }
      } else {
        logW('[媒体传输检查] 警告: 本地视频渲染器srcObject为空');
      }
    }

    // ========== 检查远程音频轨道 ==========
    if (_remoteStream != null) {
      final List<MediaStreamTrack> audioTracks =
          _remoteStream!.getAudioTracks();
      if (audioTracks.isNotEmpty) {
        final MediaStreamTrack track = audioTracks.first;
        logI(
          '[媒体传输检查] 远程音频轨道: enabled=${track.enabled}, muted=${track.muted}, label=${track.label}',
        );
        logI('[媒体传输检查] 远程流ID: ${_remoteStream!.id}');
      } else {
        logW('[媒体传输检查] 远程流存在但无音频轨道');
      }
    } else {
      logW('[媒体传输检查] 远程媒体流为空');
    }

    // ========== 检查远程视频轨道 ==========
    if (_remoteStream != null) {
      final List<MediaStreamTrack> videoTracks =
          _remoteStream!.getVideoTracks();
      if (videoTracks.isNotEmpty) {
        final MediaStreamTrack track = videoTracks.first;
        logI(
          '[媒体传输检查] 远程视频轨道: enabled=${track.enabled}, muted=${track.muted}, label=${track.label}',
        );
      } else {
        logD('[媒体传输检查] 远程流暂无视频轨道');
      }

      // 检查远程视频渲染器状态
      if (_remoteRenderer.srcObject != null) {
        final int videoWidth = _remoteRenderer.videoWidth;
        final int videoHeight = _remoteRenderer.videoHeight;
        if (videoWidth > 0 && videoHeight > 0) {
          logI('[媒体传输检查] 远程视频渲染器: ${videoWidth}x$videoHeight');
        } else {
          logD('[媒体传输检查] 远程视频渲染器未就绪');
        }
      }
    }

    // ========== 检查数据通道状态 ==========
    if (_dataChannel != null) {
      logD('[媒体传输检查] 数据通道已建立，状态: ${_dataChannel?.state}');
    } else {
      logW('[媒体传输检查] 警告: 数据通道未建立');
    }

    // ========== 检查WebRTC连接状态 ==========
    logI('[媒体传输检查] WebRTC连接状态: $_connectionStatus');
  }

  /// 解析ICE候选字符串，提取关键信息
  String _formatIceCandidate(String candidate) {
    try {
      // 解析 candidate: foundation component_id priority ip_address port typ type [raddr related_address] [rport related_port]
      final List<String> parts = candidate.split(' ');
      if (parts.length < 8) {
        return candidate;
      }

      final String transport = parts[2].toUpperCase(); // UDP/TCP
      final String address = parts[4];
      final String port = parts[5];

      // 查找类型
      String type = 'unknown';
      for (int i = 6; i < parts.length; i++) {
        if (parts[i] == 'typ' && i + 1 < parts.length) {
          type = parts[i + 1];
          break;
        }
      }

      // 根据地址格式化显示
      String displayAddress = address;
      if (address.contains(':') && !address.startsWith('[')) {
        displayAddress = '[$address]'; // IPv6地址格式化
      }

      return '[$transport] $type $displayAddress:$port';
    } catch (e) {
      return candidate; // 解析失败时返回原始字符串
    }
  }

  /// 重置ICE状态
  void _resetIceState() {
    _iceCandidateCount = 0;
    _isIceGatheringComplete = false;
    _pendingIceCandidates.clear();
    _iceCandidateBatchTimer?.cancel();
    _iceCandidateBatchTimer = null;

    if (_iceGatheringCompleter != null &&
        !_iceGatheringCompleter!.isCompleted) {
      _iceGatheringCompleter!.complete();
    }
    _iceGatheringCompleter = Completer<void>();
  }

  /// 判断是否应该重试连接 - 智能错误分类
  bool _shouldRetryConnection(Object error) {
    // 检查错误类型，决定是否应该重试
    final String errorString = error.toString().toLowerCase();

    // 可重试的错误类型 - 快速失败类型
    if (errorString.contains('timeout') ||
        errorString.contains('connection') ||
        errorString.contains('network') ||
        errorString.contains('host') ||
        errorString.contains('socket') ||
        errorString.contains('ice')) {
      logD('可重试错误: $errorString');
      return true;
    }

    // SSL证书错误可以重试（开发环境常见）
    if (errorString.contains('certificate') ||
        errorString.contains('ssl') ||
        errorString.contains('tls')) {
      logD('SSL相关错误，可重试: $errorString');
      return true;
    }

    // 不可重试的错误类型 - 立即失败
    if (errorString.contains('permission') ||
        errorString.contains('denied') ||
        errorString.contains('not found') ||
        errorString.contains('invalid')) {
      logD('不可重试错误: $errorString');
      return false;
    }

    // 其他错误默认可重试
    logD('未知错误类型，默认重试: $errorString');
    return true;
  }

  /// 计算重试延迟（快速递增策略）
  Duration _calculateRetryDelay(int attemptNumber) {
    // 使用预定义的快速递增间隔：[500ms, 1s, 2s, 5s, 10s]
    if (attemptNumber <= 0 || attemptNumber > _retryIntervals.length) {
      // 如果超出范围，使用最后一个间隔
      return Duration(milliseconds: _retryIntervals.last);
    }

    final int baseDelayMs = _retryIntervals[attemptNumber - 1];

    // 添加少量随机抖动（±10%）避免多个客户端同时重试
    final double randomFactor = 0.9 + (DateTime.now().millisecond % 20) / 200.0;
    final int finalDelayMs = (baseDelayMs * randomFactor).round();

    logD('重试延迟计算: 第$attemptNumber次尝试, ${finalDelayMs}ms');
    return Duration(milliseconds: finalDelayMs);
  }

  /// 检查请求是否重复
  bool _isDuplicateOffer(String sessionId) {
    if (_lastOfferSent == null) {
      return false;
    }

    // 由于后端生成的session_id是唯一的，不同会话的session_id不可能相同
    // 如果session_id完全相同，说明是重复的连接请求
    return _lastOfferSent == sessionId;
  }

  /// 获取设备制造商（用于诊断和平台特定处理）
  Future<String> _getDeviceManufacturer() async {
    try {
      if (Platform.isAndroid) {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        return '${androidInfo.brand} ${androidInfo.model}';
      }
      return 'iOS';
    } catch (e) {
      return 'Unknown';
    }
  }

  /// 清理资源
  Future<void> _cleanup() async {
    // 停止音频级别监控
    _audioLevelTimer?.cancel();
    _audioLevelTimer = null;
    _audioStatsTimer?.cancel();
    _audioStatsTimer = null;

    // 清理 ICE 相关资源
    _resetIceState();

    // 重置取消状态
    _isCancelling = false;

    // 关闭数据通道
    _dataChannel?.close();
    _dataChannel = null;

    // 清理视频轨道
    _videoTrack = null;
    _isVideoEnabled = false;

    // 关闭本地流
    _localStream?.getTracks().forEach((MediaStreamTrack track) {
      track.stop();
    });
    await _localStream?.dispose();

    // 停止远程音频流轨道（在断开连接时完全停止）
    _remoteStream?.getTracks().forEach((MediaStreamTrack track) {
      if (track.kind == 'audio') {
        logI('🛑 停止远程音频轨道: ${track.id}');
      }
      track.stop();
    });
    await _remoteStream?.dispose();

    // 关闭PeerConnection
    await _peerConnection?.close();

    // 清理渲染器
    _localRenderer.srcObject = null;
    _remoteRenderer.srcObject = null;

    _localStream = null;
    _remoteStream = null;
    _peerConnection = null;
    _dataChannel = null;
    _isRecording = false;
    _audioStatus = '未连接';
    _lastAudioError = '';
    _audioFrameCount = 0;
    _connectionAttempts = 0; // 重置连接尝试次数
    _lastOfferSent = null;

    notifyListeners();
  }
}
