import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:ai_assistant/core/services/websocket_manager.dart';
import 'package:ai_assistant/core/services/audio_service.dart';
import 'package:ai_assistant/core/services/audio_instant.dart';
import 'package:ai_assistant/core/config/constants.dart';
import 'package:ai_assistant/core/models/message_api.dart'
    as message_api; // 导入消息API
import 'package:ai_assistant/core/utils/app_logger.dart';
import 'package:ai_assistant/core/utils/id_generator.dart';

/// 自定义服务事件类型
enum DiyServiceEventType {
  connected,
  disconnected,
  reconnecting,
  error,
  status, // 通用状态更新，如vad, stt等
  userMessage, // 用户消息的文本
  responseText, // AI响应的文本块
  audioData, // 原始音频数据流，用于可能的实时可视化
  ttsStop, // TTS 用户中断信号
  ttsEnd, // TTS 自然完成信号
}

/// 自定义服务事件
class DiyServiceEvent {
  final DiyServiceEventType type;
  final dynamic data;

  DiyServiceEvent(this.type, this.data);
}

/// 自定义服务监听器
typedef DiyServiceListener = void Function(DiyServiceEvent event);

/// 消息监听器
typedef MessageListener = void Function(Object? message);

/// Session ID 更新回调
typedef SessionIdUpdateCallback = void Function(String? sessionId);

/// 自定义服务
class DiyService extends ChangeNotifier {
  final String _websocketUrl;
  final String _macAddress;
  final String _token;
  String? _sessionId; // 会话ID将由服务器提供

  /// 获取当前Session ID（公开访问方法）
  String? get sessionId => _sessionId;
  final SessionIdUpdateCallback? onSessionIdUpdate; // 新增回调

  // 添加getter方法用于配置比较
  String get websocketUrl => _websocketUrl;
  String get macAddress => _macAddress;
  String get token => _token;

  /// 文本通道WebSocket管理器
  DiyWebSocketManager? _textWebSocketManager;
  DiyWebSocketManager? get textWebSocketManager => _textWebSocketManager;

  /// 音频通道WebSocket管理器
  DiyWebSocketManager? _audioWebSocketManager;
  DiyWebSocketManager? get audioWebSocketManager => _audioWebSocketManager;

  /// 兼容旧代码的getter（返回文本通道）
  DiyWebSocketManager? get webSocketManager => _textWebSocketManager;

  /// 文本通道连接状态
  bool _isTextConnected = false;

  /// 音频通道连接状态
  bool _isAudioConnected = false;
  bool _isMuted = false;
  bool _isUserManualcallSpeaking = false; // 按住说话模式下用户说话状态
  final List<DiyServiceListener> _listeners = [];
  StreamSubscription? _audioStreamSubscription;
  final List<MessageListener> _messageListeners = [];
  String? _currentRequestId; // 当前活跃的请求ID

  // VoiceCall模式专用状态变量
  bool _isInVoiceCallMode = false; // 标识是否在语音通话模式
  bool _isUserVoicecallSpeaking = false; // 语音通话模式下用户说话状态
  Timer? _reconnectTimer;
  bool _shouldReconnect = false;
  bool _isReconnecting = false; // 防止并发重连
  bool _isConnectingAudioChannel = false; // 正在连接音频通道标志

  // 事件流控制器
  final _eventController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get events => _eventController.stream; // 暴露事件流

  DiyService({
    required String websocketUrl,
    required String macAddress,
    required String token,
    String? sessionId,
    this.onSessionIdUpdate,
  }) : _websocketUrl = websocketUrl,
       _macAddress = macAddress,
       _token = token {
    logI(
      '🔧 DiyService 构造函数: url=$_websocketUrl, mac=$_macAddress, sessionId=$sessionId',
    );

    _sessionId = sessionId;

    // 验证session ID状态
    if (_sessionId != null && _sessionId!.isNotEmpty) {
      logI('✅ 使用已存在的Session ID: $_sessionId');
    } else {
      logW('⚠️ Session ID为空，将创建新会话');
    }

    _init();
  }

  /// 设置语音通话模式标识（轻量级版本，避免重复初始化）
  void setVoiceCallMode(bool enabled) {
    _isInVoiceCallMode = enabled;
    _isUserVoicecallSpeaking = false;
    logI('语音通话模式标识已设置为: $enabled');
  }

  /// 验证和恢复Session ID
  void validateAndRestoreSessionId(String? sessionId) {
    logI('🔍 Session ID验证和恢复: inputSessionId=$sessionId');

    if (sessionId != null && sessionId.isNotEmpty) {
      // 验证Session ID格式（简单验证：长度和字符检查）
      if (sessionId.length >= 10 &&
          RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(sessionId)) {
        if (_sessionId != sessionId) {
          final oldSessionId = _sessionId;
          _sessionId = sessionId;
          logI('✅ Session ID已恢复: $oldSessionId → $sessionId');

          // 调用回调更新持久化存储
          if (onSessionIdUpdate != null) {
            onSessionIdUpdate!(_sessionId);
            logI('📞 Session ID恢复后已调用回调更新持久化存储');
          }
        } else {
          logI('📋 Session ID已是最新值，无需恢复: $_sessionId');
        }
      } else {
        logW('⚠️ Session ID格式无效: $sessionId');
      }
    } else {
      logW('⚠️ Session ID为空，无法恢复');
    }
  }

  /// 初始化WebSocket管理器
  Future<void> _init() async {
    logI('初始化双通道WebSocket管理器，使用MAC地址作为设备ID: $_macAddress');

    // 如果WebSocket管理器不存在，创建新的
    if (_textWebSocketManager == null) {
      _textWebSocketManager = DiyWebSocketManager(
        deviceId: _macAddress,
        channelType: 'text',
      );
      logI('文本WebSocket管理器创建完成');
    } else {
      logI('文本WebSocket管理器已存在，复用现有实例');
    }

    if (_audioWebSocketManager == null) {
      _audioWebSocketManager = DiyWebSocketManager(
        deviceId: _macAddress,
        channelType: 'audio',
      );
      logI('音频WebSocket管理器创建完成');
    } else {
      logI('音频WebSocket管理器已存在，复用现有实例');
    }

    // 关键修复：始终添加事件监听器，即使管理器已存在
    // 先移除旧的监听器（如果存在），避免重复
    _textWebSocketManager!.removeListener(_onTextWebSocketEvent);
    _textWebSocketManager!.addListener(_onTextWebSocketEvent);
    logI('文本通道事件监听器已添加/更新');

    _audioWebSocketManager!.removeListener(_onAudioWebSocketEvent);
    _audioWebSocketManager!.addListener(_onAudioWebSocketEvent);
    logI('音频通道事件监听器已添加/更新');
  }

  /// 添加消息监听器
  void addMessageListener(MessageListener listener) {
    if (!_messageListeners.contains(listener)) {
      _messageListeners.add(listener);
    }
  }

  /// 移除消息监听器
  void removeMessageListener(MessageListener listener) {
    _messageListeners.remove(listener);
  }

  /// 添加服务事件监听器
  void addServiceListener(DiyServiceListener listener) {
    if (!_listeners.contains(listener)) {
      _listeners.add(listener);
    }
  }

  /// 移除服务事件监听器
  void removeServiceListener(DiyServiceListener listener) {
    _listeners.remove(listener);
  }

  /// 新方法，供外部直接监听
  StreamSubscription<Map<String, dynamic>> listen(
    void Function(Map<String, dynamic>) listener,
  ) {
    logI(
      '🎧 [订阅] 新的监听器订阅eventController, isControllerClosed=${_eventController.isClosed}',
    );
    final subscription = _eventController.stream.listen(listener);
    logI('🎧 [订阅] 监听器订阅成功');
    return subscription;
  }

  /// 分发事件到所有监听器
  void _dispatchEvent(DiyServiceEvent event) {
    // 调试日志：记录事件分发
    logI(
      '🔔 [事件分发] 开始分发事件: type=${event.type}, hasListeners=${_listeners.isNotEmpty}, isControllerClosed=${_eventController.isClosed}',
    );

    // 复制列表以避免并发修改错误
    for (var listener in List<DiyServiceListener>.from(_listeners)) {
      try {
        listener(event);
      } catch (e, s) {
        logE('Error in listener: $e\n$s');
        // 可以选择是否移除出错的监听器，或者其他错误处理逻辑
      }
    }

    // 同时向新的事件控制器分发事件
    if (!_eventController.isClosed) {
      try {
        _eventController.add({
          'type': event.type.toString().split('.').last,
          'data': event.data,
        });
        logI('🔔 [事件分发] 事件已添加到eventController: type=${event.type}');
      } catch (e, s) {
        logE('Error adding to event controller: $e\n$s');
      }
    } else {
      logW('⚠️ [事件分发] eventController已关闭，无法分发事件');
    }
  }

  /// 重连WebSocket方法
  void _reconnectWebSocket() {
    // 检查是否应该重连（dispose后不应重连）
    if (!_shouldReconnect) {
      logI('_shouldReconnect为false，停止重连');
      return;
    }

    if (_isReconnecting) {
      logI('已在重连中，跳过重复重连');
      return;
    }

    logI('开始重连WebSocket');
    _isReconnecting = true;
    int retryCount = 0;

    // 取消之前的重连定时器
    _reconnectTimer?.cancel();

    // 使用串行重连机制，避免并发连接
    _reconnectWebsocket(retryCount);
  }

  Future<void> _reconnectWebsocket(int currentRetryCount) async {
    if (!_shouldReconnect) {
      logI('_shouldReconnect为false，停止重连');
      _isReconnecting = false;
      return;
    }

    // 检查是否已经连接
    if (_textWebSocketManager != null && _textWebSocketManager!.isConnected) {
      logI('连接已恢复，停止重连');
      _isReconnecting = false;
      return;
    }

    // 确保连接状态为false
    _isTextConnected = false;
    _isAudioConnected = false;

    currentRetryCount++;
    logI('第$currentRetryCount次重连尝试');

    if (currentRetryCount >= 20) {
      logE('达到最大重试次数，停止重连');
      _isReconnecting = false;
      _dispatchEvent(
        DiyServiceEvent(
          DiyServiceEventType.error,
          '后端服务未启动，请检查后端服务器状态',
        ),
      );
      return;
    }

    try {
      logI('准备执行连接操作...');
      await _connectToServer();

      // 如果连接成功，停止重连
      if (isConnected) {
        logI('重连成功，停止重连机制');
        _isReconnecting = false;
        return;
      }
    } catch (e) {
      logE('第$currentRetryCount次重连失败: $e');
    }

    // 等待1.5秒后进行下一次重连
    _reconnectTimer = Timer(const Duration(milliseconds: 2000), () {
      _reconnectWebsocket(currentRetryCount);
    });
  }

  /// 连接到服务器（双通道连接：先文本后音频）
  Future<void> _connectToServer() async {
    // 重置连接状态，确保可以重新尝试连接
    _isTextConnected = false;
    _isAudioConnected = false;
    logI('双通道连接状态已重置，准备连接:$_websocketUrl, _sessionId: $_sessionId');

    try {
      // 确保WebSocket管理器已初始化
      if (_textWebSocketManager == null || _audioWebSocketManager == null) {
        logI('WebSocket管理器未初始化，开始初始化...');
        await _init();
      }

      // ========== 第一步：连接文本通道 ==========
      logI('========== 第一步：连接文本通道 ==========');
      _textWebSocketManager!.setChatMode(_isMuted ? 'mute_mode' : 'usual_mode');
      logI('设置文本通道chat_mode为: ${_isMuted ? 'mute_mode' : 'usual_mode'}');

      // 注意：事件监听器已在 _init() 方法中统一添加，此处无需重复添加

      // 构建文本通道headers
      Map<String, String> textHeaders = {};
      if (_sessionId != null && _sessionId!.isNotEmpty) {
        textHeaders[HttpHeaders.xSessionId] = _sessionId!;
      }
      logI('📋 文本通道连接headers: $textHeaders');

      // 连接文本通道
      try {
        logI('准备建立文本通道WebSocket连接...');
        // _websocketUrl 已包含 /chat/v1，直接添加末尾斜杠
        await _textWebSocketManager!
            .connect('$_websocketUrl', _token, headers: textHeaders)
            .timeout(const Duration(seconds: 10));
        logI('文本通道连接请求已发送，等待连接确认...');
      } on TimeoutException {
        logE('文本通道连接超时');
        throw Exception('文本通道连接超时');
      }

      // 等待文本通道连接成功
      logI('等待文本通道连接成功...');
      await _waitForTextConnection();
      logI('✅ 文本通道连接成功');

      // ========== 第二步：条件性连接音频通道 ==========
      // 如果已有 sessionId（恢复会话场景），立即连接音频通道
      // 如果是新会话（sessionId 为 null），等待 response.hello 消息后再连接
      if (_sessionId != null && _sessionId!.isNotEmpty) {
        logI('========== 第二步：连接音频通道（已有 sessionId） ==========');
        await _connectAudioChannel();
        logI('🎉 双通道连接完成');
      } else {
        logI('⏳ 等待 response.hello 消息以获取 sessionId 后连接音频通道');
        // 设置连接中标志，这样 isConnected 返回 true，防止误触发断开连接事件
        _isConnectingAudioChannel = true;
        logI('🔄 设置 _isConnectingAudioChannel = true，使 isConnected 返回 true');
      }
    } on SocketException catch (e) {
      logE('网络连接异常: $e');
      _isTextConnected = false;
      _isAudioConnected = false;
      rethrow;
    } on WebSocketException catch (e) {
      logE('WebSocket连接异常: $e');
      _isTextConnected = false;
      _isAudioConnected = false;
      rethrow;
    } catch (e) {
      logE('连接失败: $e');
      _isTextConnected = false;
      _isAudioConnected = false;

      // 检查是否为配置错误
      _checkForConfigError(e);

      rethrow;
    }
  }

  /// 检查异常是否包含配置错误信息
  void _checkForConfigError(dynamic error) {
    try {
      // 尝试解析错误信息
      String errorString = error.toString();

      // 检查错误字符串中是否包含配置错误标记
      if (errorString.contains('is_config_error') ||
          errorString.contains('配置错误') ||
          errorString.contains('config error')) {
        logE('检测到配置错误，停止重连');
        _shouldReconnect = false; // 禁止重连
        _isReconnecting = false;

        // 提取具体错误信息
        String errorMessage = '后端服务配置错误';
        if (errorString.contains(':')) {
          // 尝试提取冒号后的具体错误信息
          final parts = errorString.split(':');
          if (parts.length > 1) {
            errorMessage = parts.sublist(1).join(':').trim();
          }
        }

        _dispatchEvent(
          DiyServiceEvent(
            DiyServiceEventType.error,
            '配置错误: $errorMessage\n请检查后端服务器配置',
          ),
        );
      }
    } catch (e) {
      logW('解析配置错误失败: $e');
    }
  }

  /// 等待文本通道连接成功
  Future<void> _waitForTextConnection() async {
    int attempts = 0;
    const maxAttempts = 50; // 最多等待5秒

    while (!_isTextConnected && attempts < maxAttempts) {
      await Future.delayed(const Duration(milliseconds: 100));
      attempts++;
    }

    if (!_isTextConnected) {
      throw Exception('文本通道连接超时');
    }
  }

  /// 等待音频通道连接成功
  Future<void> _waitForAudioConnection() async {
    int attempts = 0;
    const maxAttempts = 50; // 最多等待5秒

    while (!_isAudioConnected && attempts < maxAttempts) {
      await Future.delayed(const Duration(milliseconds: 100));
      attempts++;
    }

    if (!_isAudioConnected) {
      throw Exception('音频通道连接超时');
    }
  }

  /// 连接音频通道（独立方法，可在收到 sessionId 后调用）
  Future<void> _connectAudioChannel() async {
    if (_isAudioConnected) {
      logI('音频通道已连接，跳过');
      return;
    }

    if (_sessionId == null || _sessionId!.isEmpty) {
      logE('❌ Session ID为空，无法连接音频通道');
      return;
    }

    // 设置连接中标志，防止误触发断开连接事件
    _isConnectingAudioChannel = true;

    try {
      logI('========== 连接音频通道 ==========');
      // 注意：事件监听器已在 _init() 方法中统一添加，此处无需重复添加

      Map<String, String> audioHeaders = {HttpHeaders.xSessionId: _sessionId!};
      logI('📋 音频通道连接headers: $audioHeaders');

      await _audioWebSocketManager!
          .connect('$_websocketUrl/audio', _token, headers: audioHeaders)
          .timeout(const Duration(seconds: 10));

      await _waitForAudioConnection();
      logI('✅ 音频通道连接成功');
    } catch (e) {
      logE('音频通道连接失败: $e');
      _isAudioConnected = false;
    } finally {
      // 清除连接中标志
      _isConnectingAudioChannel = false;
    }
  }

  /// 连接到WebSocket服务
  Future<void> connectWebSocket() async {
    if (isConnected) {
      logI('已经连接，跳过连接请求');
      return;
    }

    _shouldReconnect = true;

    try {
      await _connectToServer();
    } catch (e) {
      logE('连接失败: $e');
      _isTextConnected = false;
      _isAudioConnected = false;
      _dispatchEvent(
        DiyServiceEvent(DiyServiceEventType.error, '连接自定义服务失败: $e'),
      );
      _dispatchEvent(
        DiyServiceEvent(DiyServiceEventType.disconnected, null),
      );

      // 连接失败，开始重连
      if (_shouldReconnect) {
        _reconnectWebSocket();
      }
    }
  }

  /// 断开服务连接
  Future<void> disconnectWebSocket() async {
    logI('断开双WebSocket连接');
    _shouldReconnect = false;
    _isReconnecting = false;
    _reconnectTimer?.cancel();

    if (!isConnected) {
      logI('未连接，无需断开');
      return;
    }

    try {
      await _audioStreamSubscription?.cancel();
      _audioStreamSubscription = null;

      if (AudioService.instance.isRecording) {
        await AudioService.instance.stopRecording();
      }

      // 断开文本通道
      if (_textWebSocketManager != null) {
        await _textWebSocketManager!.disconnect();
        _textWebSocketManager = null;
        _isTextConnected = false;
        logI('文本通道已断开');
      }

      // 断开音频通道
      if (_audioWebSocketManager != null) {
        await _audioWebSocketManager!.disconnect();
        _audioWebSocketManager = null;
        _isAudioConnected = false;
        logI('音频通道已断开');
      }
    } catch (e) {
      logE('断开连接失败: $e');
    }
  }

  /// 发送文本消息
  Future<void> sendTextMessage(String message) async {
    if (!isConnected || _textWebSocketManager == null) {
      await connectWebSocket();
    }
    _currentRequestId = IdGenerator.generateUniqueId(type: 'read');
    logI('发送文本消息, 新请求ID: $_currentRequestId');

    // 同步requestId到AudioService
    AudioService.instance.setCurrentRequestId(_currentRequestId);
    _textWebSocketManager!.sendTextRequest(
      message,
      requestId: _currentRequestId!,
    );
  }

  /// 文本通道事件处理器
  void _onTextWebSocketEvent(DiyEvent event) async {
    switch (event.type) {
      case DiyEventType.connected:
        logI('📝 文本通道已连接');
        _isTextConnected = true;
        _isReconnecting = false;
        _reconnectTimer?.cancel();

        // 只有双通道都连接时才分发connected事件
        if (isConnected) {
          _dispatchEvent(
            DiyServiceEvent(DiyServiceEventType.connected, null),
          );
          logI('🎉 双通道都已连接，服务可用');
        }
        break;

      case DiyEventType.disconnected:
        logI('📝 文本通道已断开');
        _isTextConnected = false;
        _dispatchEvent(
          DiyServiceEvent(DiyServiceEventType.disconnected, null),
        );

        // 文本通道断开触发重连
        if (_shouldReconnect && !_isReconnecting) {
          logI('文本通道断开，启动重连机制...');
          _reconnectWebSocket();
        }
        break;

      case DiyEventType.message:
        _handleTextOnlyMessage(event.data as String);
        break;

      case DiyEventType.error:
        logE('📝 文本通道错误: ${event.data}');
        _isTextConnected = false;

        // 检查是否为配置错误
        final bool isConfigError = _checkIfConfigError(event.data);
        if (isConfigError) {
          // 配置错误不触发重连
          logE('检测到配置错误，停止重连机制');
          _shouldReconnect = false;
          _isReconnecting = false;
          _reconnectTimer?.cancel();

          String errorMessage = _extractConfigErrorMessage(event.data);
          _dispatchEvent(
            DiyServiceEvent(
              DiyServiceEventType.error,
              '配置错误: $errorMessage\n请检查后端服务器配置',
            ),
          );
        } else {
          // 其他错误正常处理并触发重连
          _dispatchEvent(
            DiyServiceEvent(DiyServiceEventType.error, event.data),
          );

          // 文本通道错误触发重连
          if (_shouldReconnect && !_isReconnecting) {
            logI('文本通道错误，启动重连机制...');
            _reconnectWebSocket();
          }
        }
        break;

      case DiyEventType.binaryMessage:
        // 文本通道不应收到二进制消息
        logW('⚠️ 文本通道收到意外的二进制消息');
        break;
    }
  }

  /// 音频通道事件处理器
  void _onAudioWebSocketEvent(DiyEvent event) async {
    switch (event.type) {
      case DiyEventType.connected:
        logI('🎵 音频通道已连接');
        _isAudioConnected = true;
        _isReconnecting = false;
        _reconnectTimer?.cancel();

        // 只有双通道都连接时才分发connected事件
        if (isConnected) {
          _dispatchEvent(
            DiyServiceEvent(DiyServiceEventType.connected, null),
          );
          logI('🎉 双通道都已连接，服务可用');
        }
        break;

      case DiyEventType.disconnected:
        logW('🎵 音频通道已断开（不影响文本显示）');
        _isAudioConnected = false;
        // 音频通道断开不触发全局disconnected事件
        // 但可以发送一个警告事件
        _dispatchEvent(
          DiyServiceEvent(DiyServiceEventType.status, {
            'audio_channel': 'disconnected',
          }),
        );
        break;

      case DiyEventType.message:
        _handleAudioOnlyMessage(event.data as String);
        break;

      case DiyEventType.error:
        logE('🎵 音频通道错误: ${event.data}');
        _isAudioConnected = false;
        // 音频通道错误仅记录日志，不影响文本显示
        _dispatchEvent(
          DiyServiceEvent(DiyServiceEventType.status, {
            'audio_channel': 'error',
            'error': event.data.toString(),
          }),
        );
        break;

      case DiyEventType.binaryMessage:
        // 音频通道不应收到二进制消息（音频通过JSON传输）
        logW('⚠️ 音频通道收到意外的二进制消息');
        break;
    }
  }

  /// 处理文本通道消息（仅处理文本类型）
  void _handleTextOnlyMessage(String message) {
    try {
      final Map<String, dynamic> data = json.decode(message);
      final type = data['type'];

      // 复制列表以避免在迭代期间修改列表
      for (var listener in List<MessageListener>.from(_messageListeners)) {
        try {
          listener(data);
        } catch (e, s) {
          logE('Error in message listener: $e\n$s');
        }
      }

      if (type?.startsWith('response.') == true) {
        final messageInfo = message_api.parseResponse(data);
        final newSessionId = message_api.getSessionId(
          messageInfo,
        );
        final newSessionRequestId = message_api.getSessionRequestId(
          messageInfo,
        );

        // 更新Session ID
        if (newSessionId != null && _sessionId != newSessionId) {
          final oldSessionId = _sessionId;
          _sessionId = newSessionId;
          logI('🔄 Session ID更新: $oldSessionId → $_sessionId');

          // 调用回调更新持久化存储
          if (onSessionIdUpdate != null) {
            logI('📞 调用onSessionIdUpdate回调: newSessionId=$_sessionId');
            onSessionIdUpdate!(_sessionId);
          } else {
            logW('⚠️ onSessionIdUpdate回调为null，无法持久化Session ID');
          }

          // 如果音频通道未连接且 sessionId 已获取，自动连接音频通道
          if (_audioWebSocketManager != null && !_isAudioConnected) {
            logI('🔄 收到 Session ID，自动连接音频通道...');
            _connectAudioChannel();
          }
        } else if (newSessionId == null) {
          logW('⚠️ 后端返回的Session ID为null');
        }

        // 处理STT结果
        if (message_api.isSttResponse(messageInfo)) {
          final text =
              message_api.getTextSource(messageInfo) ?? '';
          if (_isInVoiceCallMode && text.isNotEmpty) {
            // VoiceCall模式下，用户说话结束，更新状态
            _isUserVoicecallSpeaking = false;
            logI('VoiceCall模式用户说话状态更新为: false');
          }
          // STT响应也包含session_request_id，与助手响应保持一致
          _dispatchEvent(
            DiyServiceEvent(DiyServiceEventType.userMessage, {
              'text': text,
              'session_request_id': newSessionRequestId ?? '',
            }),
          );
        }

        // ⚠️ 文本通道不再处理TTS音频消息（response.tts.audio）
        // 这些消息现在由音频通道处理

        // 处理LLM流式响应
        if (message_api.isLlmStreamResponse(messageInfo)) {
          final text =
              message_api.getTextSource(messageInfo) ?? '';
          if (text.isNotEmpty) {
            _dispatchEvent(
              DiyServiceEvent(DiyServiceEventType.responseText, {
                'text': text,
                'session_request_id': newSessionRequestId ?? '',
                'is_first_chunk': message_api.isFirstChunk(
                  messageInfo,
                ),
              }),
            );
          }
        } else if (message_api.isTtsResponse(messageInfo)) {
          // 处理TTS状态消息（非音频数据）
          final audioPlaybackStatus = message_api.getAudioPlaybackStatus(
            messageInfo,
          );
          if (audioPlaybackStatus != null) {
            final state = audioPlaybackStatus.state;
            if (state == message_api.AudioPlaybackStatus.stateEnd) {
              if (newSessionRequestId == _currentRequestId) {
                logI('TTS自然播放结束, request_id: $newSessionRequestId');
                _dispatchEvent(
                  DiyServiceEvent(DiyServiceEventType.ttsEnd, null),
                );
              }
            } else if (state == message_api.AudioPlaybackStatus.stateStop) {
              logI('TTS被强制中断, request_id: $newSessionRequestId');
              stopPlayback();
            }
          }
        } else if (message_api.isErrorResponse(messageInfo)) {
          // 处理错误消息
          logE('收到错误响应: $data');

          // 检查是否为配置错误
          final bool isConfigError = _checkIfConfigError(data);
          if (isConfigError) {
            // 配置错误不触发重连
            logE('检测到配置错误，停止重连机制');
            _shouldReconnect = false;
            _isReconnecting = false;
            _reconnectTimer?.cancel();

            String errorMessage = _extractConfigErrorMessage(data);
            _dispatchEvent(
              DiyServiceEvent(
                DiyServiceEventType.error,
                '配置错误: $errorMessage\n请检查后端服务器配置',
              ),
            );
          } else {
            // 其他错误正常处理
            _dispatchEvent(
              DiyServiceEvent(DiyServiceEventType.error, data),
            );
          }
        }
      }
    } catch (e, s) {
      logE('处理文本消息失败: $e\n$s');
    }
  }

  /// 处理音频通道消息（仅处理音频类型）
  void _handleAudioOnlyMessage(String message) {
    try {
      final Map<String, dynamic> data = json.decode(message);
      final type = data['type'];

      // 音频通道只处理TTS音频消息
      // 注意：正确的事件类型是 response.tts.audio（点号分隔）
      if (type == 'response.tts.audio') {
        final messageInfo = message_api.parseResponse(data);
        final audioBytes = message_api.getAudioSource(
          messageInfo,
        );
        final newSessionRequestId = message_api.getSessionRequestId(
          messageInfo,
        );

        if (audioBytes != null && newSessionRequestId != null) {
          _handleAudioWithRequestId(audioBytes, newSessionRequestId);
        }
      } else {
        // 音频通道收到非音频消息，记录警告
        logW('⚠️ 音频通道收到非音频消息类型: $type');
      }
    } catch (e, s) {
      logE('处理音频消息失败: $e\n$s');
    }
  }

  /// 开始听说（语音通话模式）
  Future<void> startListeningCall() async {
    // 防止重复调用 - 使用VoiceCall模式状态检查
    if (_isInVoiceCallMode && _isUserVoicecallSpeaking) {
      logW('startListeningCall 被重复调用，忽略');
      return;
    }

    // 权限检查
    if (Platform.isIOS || Platform.isAndroid) {
      final status = await Permission.microphone.request();
      if (status != PermissionStatus.granted) {
        _dispatchEvent(
          DiyServiceEvent(DiyServiceEventType.error, '麦克风权限被拒绝'),
        );
        return;
      }
    }

    // 确保连接
    if (!isConnected) {
      logW('startListeningCall: 未连接，先连接服务器');
      await connectWebSocket();
    }

    // 再次检查连接状态
    if (!isConnected) {
      logE('startListeningCall: 连接失败，无法开始录音');
      return;
    }

    // 生成新的请求ID
    _currentRequestId = IdGenerator.generateUniqueId(type: 'listen');

    // 同步requestId到AudioService
    AudioService.instance.setCurrentRequestId(_currentRequestId);

    logI('VoiceCall模式开始录音，RequestId: $_currentRequestId');

    // 发送监听开始消息 - 使用auto模式
    await sendListenMessage(
      state: message_api.PlaybackState.start,
      mode: message_api.PlaybackMode.auto, // 关键：auto模式让VAD控制停止
    );
    logI('已发送监听开始消息');

    // 设置播放状态
    AudioService.instance.setPlaybackState(true);

    // 开始录音
    await AudioService.instance.startRecording();
    _audioStreamSubscription = AudioService.instance.audioStream.listen((
      opusData,
    ) {
      if (_isInVoiceCallMode) {
        // 只在VoiceCall模式下发送音频
        _textWebSocketManager?.sendBinaryMessage(opusData);
      }
    });

    _isUserVoicecallSpeaking = true;
    logI('录音流已启动');
  }

  /// 停止听说（语音通话模式）
  Future<void> stopListeningCall() async {
    logI('VoiceCall模式停止录音，RequestId: $_currentRequestId');

    // 发送中断消息，停止后端TTS生成
    await sendAbortMessage();
    // 设置播放状态
    AudioService.instance.setPlaybackState(false);

    // 取消音频流订阅
    await _audioStreamSubscription?.cancel();
    _audioStreamSubscription = null;

    // 停止录音
    await AudioService.instance.stopRecording();
    // 更新用户说话状态
    _isUserVoicecallSpeaking = false;

    // 发送停止监听消息给后端
    await sendListenMessage(
      state: message_api.PlaybackState.stop,
      mode: message_api.PlaybackMode.auto, // 使用auto模式停止
    );
  }

  /// 开始监听（按住说话模式）
  Future<void> startRecording() async {
    logI('开始按住说话...');

    // 检查连接状态
    if (!isConnected) {
      await connectWebSocket();
    }

    _isUserManualcallSpeaking = true;

    // 设置新requestId及状态
    _currentRequestId = IdGenerator.generateUniqueId(type: 'listen');

    // 同步requestId到AudioService
    AudioService.instance.setCurrentRequestId(_currentRequestId);

    await sendListenMessage(
      state: message_api.PlaybackState.start,
      mode: message_api.PlaybackMode.manual,
    );

    // 音频系统已由AudioService初始化，直接开始录音
    AudioService.instance.setPlaybackState(false);
    await AudioService.instance.startRecording();
    _audioStreamSubscription = AudioService.instance.audioStream.listen((
      opusData,
    ) {
      if (_isUserManualcallSpeaking) {
        _audioWebSocketManager?.sendBinaryMessage(opusData);
      }
    });
    logI('开始启动录音...');
  }

  /// 停止监听（按住说话模式）
  Future<void> stopRecording() async {
    if (!_isUserManualcallSpeaking) {
      return;
    }

    await sendListenMessage(
      state: message_api.PlaybackState.stop,
      mode: message_api.PlaybackMode.manual,
    );
    // 在发送消息后设置为false
    _isUserManualcallSpeaking = false;

    // 停止音频流
    await _audioStreamSubscription?.cancel();
    _audioStreamSubscription = null;
    if (AudioService.instance.isRecording) {
      await AudioService.instance.stopRecording();
    }

    // 启动播放状态，准备接收AI响应
    AudioService.instance.setPlaybackState(true);
  }

  /// 强制停止录音器（用于取消录音场景）
  Future<void> cancelStopRecording() async {
    // 发送中断消息，停止后端TTS生成
    await sendAbortMessage();
    // 设置播放状态
    AudioService.instance.setPlaybackState(false);

    // 停止音频流
    await _audioStreamSubscription?.cancel();
    _audioStreamSubscription = null;

    // 重置状态
    _isUserManualcallSpeaking = false;

    // 停止录音器但不发送stop消息
    if (AudioService.instance.isRecording) {
      await AudioService.instance.stopRecording();
    }
  }

  /// 统一处理音频播放 - 简化版本（优化context创建）
  Future<void> _handleAudioWithRequestId(
    Uint8List audioData,
    String requestId,
  ) async {
    final AudioMode mode =
        _isInVoiceCallMode ? AudioMode.voiceCall : AudioMode.chat;

    // 使用工厂方法创建context，减少对象分配
    final AudioPlayContext context =
        _isInVoiceCallMode
            ? AudioPlayContext.forVoiceCall(
              requestId: requestId,
              currentRequestId: _currentRequestId,
              isUserSpeaking: _isUserVoicecallSpeaking,
            )
            : AudioPlayContext.forChat(
              requestId: requestId,
              currentRequestId: _currentRequestId,
              isUserSpeaking: _isUserManualcallSpeaking,
            );

    // 使用AudioService的统一判断方法
    if (AudioService.instance.validateAudioPlaybackReadiness(context)) {
      await _startAudioPlayback(audioData, mode, context: context);
    }
  }

  /// 执行音频播放
  Future<void> _startAudioPlayback(
    Uint8List audioData,
    AudioMode mode, {
    AudioPlayContext? context,
  }) async {
    try {
      switch (mode) {
        case AudioMode.voiceCall:
          await AudioService.instance.startPlayback(
            audioData: audioData,
            format: AudioFormat.opus,
            enableWebRTC: true,
            context: context,
          );
          break;
        case AudioMode.chat:
          await AudioService.instance.startPlayback(
            audioData: audioData,
            format: AudioFormat.opus,
            enableWebRTC: false,
            context: context,
          );
          break;
        default:
          logE('不支持的音频模式: $mode');
          break;
      }
    } catch (e) {
      logE('音频播放失败: $e');
    }
  }

  /// 停止播放并清理状态
  Future<void> stopPlayback() async {
    logI('外部调用停止播放，清理状态');
    _isUserManualcallSpeaking = false;
    AudioService.instance.setPlaybackState(false);
    _dispatchEvent(DiyServiceEvent(DiyServiceEventType.ttsStop, null));
  }

  /// 发送中断消息
  Future<void> sendAbortMessage() async {
    if (_textWebSocketManager != null && _isTextConnected) {
      final sessionRequestId = IdGenerator.generateUniqueId(type: 'abort');
      final abortRequest = message_api.createAbortRequest(
        sessionId: _sessionId ?? '',
        sessionRequestId: sessionRequestId,
      );
      _textWebSocketManager?.sendMessage(jsonEncode(abortRequest.toJson()));
      logI('发送中断消息，session_request_id: $sessionRequestId');
      // 设置当前请求ID
      _currentRequestId = sessionRequestId;
      AudioService.instance.setCurrentRequestId(_currentRequestId);
    }
  }

  /// 发送监听消息的统一接口
  Future<void> sendListenMessage({
    required message_api.PlaybackState state,
    required message_api.PlaybackMode mode,
  }) async {
    final message = message_api.createListenRequest(
      sessionId: _sessionId ?? '',
      audioPlaybackStatus: message_api.AudioPlaybackStatus(
        state: state,
        mode: mode,
      ),
      sessionRequestId: _currentRequestId!,
      audioParams: message_api.AudioParams(
        format: message_api.AudioFormat.opus,
        sampleRate: 16000,
        channels: 1,
        frameDuration: 60,
      ),
    );
    _textWebSocketManager?.sendMessage(jsonEncode(message.toJson()));
  }

  /// 判断是否已连接
  /// 新会话场景：文本通道连接成功且正在连接音频通道时也视为已连接
  bool get isConnected {
    if (_isConnectingAudioChannel && _isTextConnected) {
      return true; // 正在连接音频通道时，暂时认为已连接
    }
    return _isTextConnected && _isAudioConnected;
  }

  /// 判断是否静音
  bool get isMuted => _isMuted;

  /// 发送静音事件到后端
  void sendMuteEvent(bool isMuted) {
    logI('发送静音事件到后端: $isMuted');
    _textWebSocketManager?.sendMuteEvent(isMuted);
  }

  void setMute(bool mute) {
    if (_isMuted != mute) {
      logI('DiyService.setMute: $_isMuted -> $mute');
      _isMuted = mute;
      _textWebSocketManager?.setChatMode(mute ? 'mute_mode' : 'usual_mode');

      // 设置静音状态
      AudioService.instance.setMuteState(mute);
      //
      _dispatchEvent(
        DiyServiceEvent(DiyServiceEventType.status, {
          'isMuted': _isMuted,
        }),
      );
    } else {
      logI('DiyService.setMute: 状态无变化，保持 $mute');
    }
  }

  @override
  void dispose() {
    logI('开始释放资源...');
    _shouldReconnect = false;
    _isReconnecting = false;
    _reconnectTimer?.cancel();

    // 断开双通道连接
    if (_textWebSocketManager != null) {
      _textWebSocketManager!.disconnect();
      _textWebSocketManager = null;
    }
    if (_audioWebSocketManager != null) {
      _audioWebSocketManager!.disconnect();
      _audioWebSocketManager = null;
    }

    _eventController.close();
    super.dispose();
    logI('资源释放完成');
  }

  /// 检查错误数据是否包含配置错误标记
  ///
  /// [errorData] 错误数据，可以是String或Map<String, dynamic>
  ///
  /// 返回 true 如果是配置错误，否则返回 false
  bool _checkIfConfigError(dynamic errorData) {
    try {
      // 如果是字符串，尝试解析为JSON
      Map<String, dynamic>? errorMap;
      if (errorData is String) {
        try {
          errorMap = json.decode(errorData) as Map<String, dynamic>;
        } catch (e) {
          // 如果不是有效的JSON，检查字符串内容
          final String errorString = errorData.toLowerCase();
          return errorString.contains('is_config_error') ||
              errorString.contains('配置错误') ||
              errorString.contains('config error');
        }
      } else if (errorData is Map) {
        errorMap = errorData as Map<String, dynamic>;
      }

      // 检查配置错误标记
      if (errorMap != null) {
        // 检查 is_config_error 字段
        if (errorMap['is_config_error'] == true) {
          return true;
        }

        // 检查错误消息中是否包含配置错误关键词
        final String? errorMessage = errorMap['message']?.toString();
        if (errorMessage != null) {
          final String lowerMessage = errorMessage.toLowerCase();
          return lowerMessage.contains('config error') ||
              lowerMessage.contains('配置错误') ||
              lowerMessage.contains('api key') ||
              lowerMessage.contains('service not configured');
        }
      }

      return false;
    } catch (e) {
      logW('检查配置错误时发生异常: $e');
      return false;
    }
  }

  /// 从错误数据中提取配置错误消息
  ///
  /// [errorData] 错误数据，可以是String或Map<String, dynamic>
  ///
  /// 返回提取的错误消息字符串
  String _extractConfigErrorMessage(dynamic errorData) {
    try {
      Map<String, dynamic>? errorMap;
      if (errorData is String) {
        try {
          errorMap = json.decode(errorData) as Map<String, dynamic>;
        } catch (e) {
          // 如果不是有效的JSON，直接返回字符串
          return errorData;
        }
      } else if (errorData is Map) {
        errorMap = errorData as Map<String, dynamic>;
      }

      if (errorMap != null) {
        // 优先返回 message 字段
        if (errorMap['message'] != null) {
          return errorMap['message'].toString();
        }

        // 其次返回 error 字段
        if (errorMap['error'] != null) {
          return errorMap['error'].toString();
        }

        // 最后返回 detail 字段
        if (errorMap['detail'] != null) {
          return errorMap['detail'].toString();
        }
      }

      // 如果无法提取，返回默认消息
      return '未知配置错误';
    } catch (e) {
      logW('提取配置错误消息时发生异常: $e');
      return '配置错误解析失败';
    }
  }
}
