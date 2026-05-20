import 'dart:async';
import 'dart:convert';
import 'dart:io'; // 添加IO支持，用于SSL配置
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:web_socket_channel/io.dart'
    if (dart.library.html) 'package:web_socket_channel/html.dart';
import 'package:ai_assistant/core/config/constants.dart'; // Import HttpHeaders
import 'package:ai_assistant/core/models/message_api.dart'; // 导入消息API
import 'package:ai_assistant/core/utils/app_logger.dart';
import 'package:ai_assistant/core/utils/id_generator.dart';

/// 自定义WebSocket事件类型
enum DiyEventType { connected, disconnected, message, error, binaryMessage }

/// 自定义WebSocket事件
class DiyEvent {
  final DiyEventType type;
  final dynamic data;

  DiyEvent({required this.type, this.data});
}

/// 自定义WebSocket监听器接口
typedef DiyWebSocketListener = void Function(DiyEvent event);

/// 自定义WebSocket管理器
class DiyWebSocketManager {
  WebSocketChannel? _channel;
  final String? _deviceId;
  final String _channelType; // 通道类型：'text' 或 'audio'
  String _currentChatMode = 'usual_mode'; // 当前的chat_mode状态
  bool _allowSelfSignedCertificates = true; // 是否允许自签名证书（开发环境）

  final List<DiyWebSocketListener> _listeners = [];
  StreamSubscription? _streamSubscription;

  /// 构造函数
  ///
  /// [deviceId] 设备ID
  /// [channelType] 通道类型，'text'表示文本通道，'audio'表示音频通道
  DiyWebSocketManager({
    required String deviceId,
    String channelType = 'text',
  }) : _deviceId = deviceId,
       _channelType = channelType {
    logI('创建WebSocket管理器: 通道类型=$_channelType, 设备ID=$_deviceId');
  }

  /// 设置当前的chat_mode状态
  void setChatMode(String chatMode) {
    _currentChatMode = chatMode;
  }

  /// 创建SSL上下文（用于WSS连接）
  SecurityContext? _createSecurityContext(bool isWss) {
    if (!isWss) {
      return null;
    }

    try {
      SecurityContext context = SecurityContext();

      // 在开发环境中，允许自签名证书
      if (_allowSelfSignedCertificates) {
        logI('开发模式：允许自签名证书');
        // 注意：在生产环境中应该移除这个设置
      }

      return context;
    } catch (e) {
      logE('SSL上下文创建失败: $e');
      return null;
    }
  }

  /// 设置是否允许自签名证书（开发环境使用）
  void setAllowSelfSignedCertificates(bool allow) {
    _allowSelfSignedCertificates = allow;
    logI('自签名证书设置: $allow');
  }

  /// 添加事件监听器
  void addListener(DiyWebSocketListener listener) {
    if (!_listeners.contains(listener)) {
      _listeners.add(listener);
    }
  }

  /// 移除事件监听器
  void removeListener(DiyWebSocketListener listener) {
    _listeners.remove(listener);
  }

  /// 分发事件到所有监听器
  void _dispatchEvent(DiyEvent event) {
    for (var listener in List.from(_listeners)) {
      // Iterate over a copy
      try {
        listener(event);
      } catch (e, s) {
        logE('Error in listener: $e\n$s');
      }
    }
  }

  /// 连接到WebSocket服务器
  Future<void> connect(
    String url,
    String token, {
    Map<String, String>? headers,
  }) async {
    if (url.isEmpty) {
      _dispatchEvent(
        DiyEvent(type: DiyEventType.error, data: "WebSocket地址不能为空"),
      );
      return;
    }

    // 每次连接前都先清理状态，确保一致的行为
    await _cleanupConnection();

    try {
      // 创建WebSocket连接
      Uri connectUri = Uri.parse(url);
      Map<String, String> effectiveHeaders = {...(headers ?? {})};

      // Add deviceId to headers if available
      if (_deviceId != null && _deviceId.isNotEmpty) {
        effectiveHeaders[HttpHeaders.deviceId] = _deviceId; // Use constant
      }

      // 🔍 诊断：打印发送的headers
      logI('🔍 准备发送的headers: $effectiveHeaders');
      logI('🔍 deviceId字段名: ${HttpHeaders.deviceId}');
      logI('🔍 deviceId值: $_deviceId');

      // Handle token: add to Authorization header for Bearer token authentication
      // The backend expects token in Authorization header, not in URL query parameters
      if (token.isNotEmpty) {
        effectiveHeaders[HttpHeaders.authorization] = 'Bearer $token';
      }

      logI('正在连接 $connectUri');
      logI('设备ID: $_deviceId');
      logI('使用Token: $token');

      // 检查是否为WSS连接
      bool isWss = connectUri.scheme.toLowerCase() == 'wss';
      SecurityContext? securityContext = _createSecurityContext(isWss);

      // 使用IOWebSocketChannel并传递headers和SSL上下文
      if (isWss && securityContext != null) {
        logI('使用WSS连接，SSL上下文已配置');
        _channel = IOWebSocketChannel.connect(
          connectUri,
          headers: effectiveHeaders,
          customClient: HttpClient(context: securityContext)
            ..badCertificateCallback =
                _allowSelfSignedCertificates
                    ? (cert, host, port) {
                      logI('接受自签名证书: $host:$port');
                      return true; // 开发环境允许自签名证书
                    }
                    : null,
        );
      } else {
        // 标准WebSocket连接
        logI('使用标准WebSocket连接');
        _channel = IOWebSocketChannel.connect(
          connectUri,
          headers: effectiveHeaders,
        );
      }

      logI('WebSocket通道已创建，等待连接确认...');

      // 等待WebSocket握手完成，设置连接超时
      try {
        await _channel!.ready.timeout(const Duration(seconds: 10));
        logI('WebSocket握手完成，连接已建立。');
      } on TimeoutException {
        logE('WebSocket连接超时：3秒内未完成握手');
        throw Exception('WebSocket连接超时');
      }

      // 监听WebSocket事件
      _streamSubscription = _channel!.stream.listen(
        _onMessage,
        onDone: () async => await _onDisconnected(),
        onError: (error) async => await _onError(error),
        cancelOnError: false,
      );

      // 只有在真正连接后才分发事件
      _dispatchEvent(
        DiyEvent(type: DiyEventType.connected, data: null),
      );

      // 发送Hello消息，包含当前的chat_mode状态
      _sendHelloMessage();

      logI('已连接到 $connectUri');
    } catch (e) {
      logE('连接失败: $e');
      _dispatchEvent(
        DiyEvent(type: DiyEventType.error, data: "WebSocket连接失败: $e"),
      );
      // 确保触发断开流程以进行重连
      _onDisconnected();
    }
  }

  /// 清理连接状态
  Future<void> _cleanupConnection() async {
    final statusBefore = connectionStatus;
    logI('清理WebSocket连接状态 - 当前状态: $statusBefore');

    // 取消订阅
    if (_streamSubscription != null) {
      logI('取消流订阅');
      await _streamSubscription!.cancel();
      _streamSubscription = null;
    }

    // 关闭连接
    if (_channel != null) {
      try {
        logI('关闭WebSocket通道');
        // 添加超时处理，避免卡在关闭过程中
        await _channel!.sink
            .close(status.normalClosure)
            .timeout(const Duration(seconds: 2));
      } on TimeoutException {
        logW('关闭WebSocket连接超时，强制关闭');
        // 强制清理
        _channel = null;
      } catch (e) {
        logW('关闭WebSocket连接时出错: $e');
      } finally {
        _channel = null;
      }
    }

    final statusAfter = connectionStatus;
    logI('WebSocket连接状态已清理 - 清理后状态: $statusAfter');
  }

  /// 断开WebSocket连接
  Future<void> disconnect() async {
    logI('断开WebSocket连接');
    await _cleanupConnection();
    logI('连接已断开');
  }

  /// 发送静音事件消息
  void sendMuteEvent(bool isMuted) {
    try {
      // 生成session_request_id
      final sessionRequestId = IdGenerator.generateUniqueId(type: 'mute');

      // 创建静音请求
      final muteRequest = createMuteRequest(
        sessionId: '', // sessionId 由后端管理
        sessionRequestId: sessionRequestId,
        chatMode: isMuted ? 'mute_mode' : 'usual_mode',
      );

      final jsonMessage = muteRequest.toJson();
      sendMessage(jsonEncode(jsonMessage));
      logI(
        '发送静音事件: $isMuted, session_request_id: $sessionRequestId, chat_mode: ${isMuted ? 'mute_mode' : 'usual_mode'}',
      );
    } catch (e) {
      logE('发送静音事件失败: $e');
    }
  }

  /// 发送Hello消息
  void _sendHelloMessage() {
    // 生成session_request_id
    final sessionRequestId = IdGenerator.generateUniqueId(type: 'hello');

    // 使用当前的chat_mode状态
    final helloRequest = createHelloRequest(
      sessionRequestId: sessionRequestId,
      chatMode: _currentChatMode,
    );
    final message = helloRequest.toJson();
    sendMessage(jsonEncode(message));
    logI(
      '已发送Hello消息，session_request_id: $sessionRequestId, chat_mode: $_currentChatMode',
    );
  }

  /// 发送文本消息
  void sendMessage(String message) {
    if (_channel != null && isConnected) {
      _channel!.sink.add(message);
    } else {
      logE('发送失败，连接未建立');
    }
  }

  /// 发送二进制数据
  void sendBinaryMessage(List<int> data) {
    if (_channel != null && isConnected) {
      try {
        _channel!.sink.add(data);
      } catch (e) {
        logE('二进制数据发送失败: $e');
      }
    } else {
      logE('发送失败，连接未建立');
    }
  }

  /// 发送文本请求
  void sendTextRequest(String text, {String? requestId}) {
    if (!isConnected) {
      logE('发送失败，连接未建立');
      return;
    }

    try {
      // 使用新的message_api创建request.read请求
      final readRequest = createReadRequest(
        sessionId: '', // 会话ID由服务器管理
        textSource: text,
        sessionRequestId: requestId,
      );

      final jsonMessage = readRequest.toJson();

      logI('发送文本请求: ${jsonEncode(jsonMessage)}');
      sendMessage(jsonEncode(jsonMessage));
    } catch (e) {
      logE('发送文本请求失败: $e');
    }
  }

  /// 发送配置更新请求
  void sendConfigRequest({
    required String sessionId,
    required Map<String, dynamic> modelConfig,
    String? requestId,
  }) {
    if (!isConnected) {
      logE('发送失败，连接未建立');
      return;
    }

    try {
      // 使用message_api创建request.config请求
      final configRequest = createConfigRequest(
        sessionId: sessionId,
        modelConfig: modelConfig,
        sessionRequestId: requestId,
      );

      final jsonMessage = configRequest.toJson();

      logI('发送配置更新请求: ${jsonEncode(jsonMessage)}');
      sendMessage(jsonEncode(jsonMessage));
    } catch (e) {
      logE('发送配置更新请求失败: $e');
    }
  }

  /// 处理收到的消息
  void _onMessage(message) {
    if (message is String) {
      // 文本消息
      // 检查是否为包含音频数据的消息，如果是则不打印
      try {
        final Map<String, dynamic> data = json.decode(message);
        final type = data['type'];

        // 只有非音频类型的消息才打印日志，减少音频数据的噪音
        if (type != 'response.tts.audio') {
          logI('收到消息: $message');
        }
      } catch (e) {
        // 如果解析失败，说明可能不是JSON格式，打印原始消息
        logI('收到消息: $message');
      }

      _dispatchEvent(
        DiyEvent(type: DiyEventType.message, data: message),
      );
    } else if (message is List<int>) {
      // 二进制消息
      _dispatchEvent(
        DiyEvent(type: DiyEventType.binaryMessage, data: message),
      );
    }
  }

  /// 处理断开连接事件
  Future<void> _onDisconnected() async {
    logI('连接已断开，开始清理资源');

    // 确保完全清理连接状态
    await _cleanupConnection();

    _dispatchEvent(
      DiyEvent(type: DiyEventType.disconnected, data: null),
    );
  }

  /// 处理错误事件
  Future<void> _onError(error) async {
    logE('错误: $error');
    _dispatchEvent(
      DiyEvent(type: DiyEventType.error, data: error.toString()),
    );

    // 任何流错误都应视为连接断开，并触发重连逻辑
    await _onDisconnected();
  }

  /// 判断是否已连接
  bool get isConnected {
    return _channel != null && _streamSubscription != null;
  }

  /// 获取连接状态（用于调试）
  String get connectionStatus {
    if (_channel == null) {
      return '未初始化';
    }
    if (_streamSubscription == null) {
      return '无订阅';
    }
    return '已连接';
  }
}
