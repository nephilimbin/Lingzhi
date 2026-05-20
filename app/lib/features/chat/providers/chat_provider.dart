import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ai_assistant/core/models/conversation.dart';
import 'package:ai_assistant/core/models/message.dart';
import 'package:ai_assistant/core/models/dify_config.dart';
import 'package:ai_assistant/core/models/diy_config.dart';
import 'package:ai_assistant/core/providers/conversation_provider.dart';
import 'package:ai_assistant/core/providers/config_provider.dart';
import 'package:ai_assistant/core/api/dify_api.dart';
import 'package:ai_assistant/core/api/diy_api.dart';
import 'package:ai_assistant/core/services/audio_service.dart';
import 'package:ai_assistant/core/services/audio_instant.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_assistant/core/providers/diy_service_provider.dart';
import 'package:ai_assistant/core/utils/app_logger.dart';
import 'package:ai_assistant/core/utils/id_generator.dart';
import 'package:ai_assistant/features/telephony/screens/telephony_screen.dart';
import 'package:permission_handler/permission_handler.dart';

enum ConnectionStatus {
  connecting,
  connected,
  reconnecting,
  disconnected,
  configMissing,
}

/// 对话框类型枚举
enum DialogType { connectionError }

/// 对话框控制器
class DialogController {
  final VoidCallback? onDismiss;
  final VoidCallback? onRetry;

  DialogController({this.onDismiss, this.onRetry});

  void dismiss() {
    onDismiss?.call();
  }

  void retry() {
    onRetry?.call();
  }
}

class ChatProvider extends ChangeNotifier with WidgetsBindingObserver {
  final Conversation conversation;
  final ConversationProvider conversationProvider;
  final DiyServiceProvider diyServiceProvider;
  final ConfigProvider configProvider;
  final BuildContext context;

  final TextEditingController textController = TextEditingController();
  final ScrollController scrollController = ScrollController();
  final FocusNode textFocusNode = FocusNode();

  DiyService? _diyService;
  DifyService? _difyService;
  ConnectionStatus _connectionStatus = ConnectionStatus.disconnected;
  StreamSubscription? _serviceSubscription;

  bool _isVoiceInputMode = false;
  bool _isRecording = false;
  bool _isCancelling = false;
  bool _isSoundPlaybackEnabled = true;
  double? _fontSize; // 聊天字体大小设置

  // 防重复弹窗状态管理（仅保留WebSocket连接错误相关）
  bool _isConnectionErrorDialogShown = false; // 连接错误对话框是否已显示

  // Dialog上下文引用管理（用于实际关闭Dialog）
  BuildContext? _activeConnectionDialogContext;
  final double _cancelThreshold = 30.0;
  bool _userInteractedWithScroll = false;
  final double _scrollThreshold = 200.0;
  bool _initialScrollPending = true;
  bool _hasText = false;
  bool _isLoadingMore = false;

  // 独立的等待状态管理
  bool _isUserWaiting = false;
  bool _isAssistantWaiting = false;

  // dispose标志，防止dispose后显示对话框
  bool _disposed = false;

  // 新增：手势稳定性保护变量
  DateTime? _lastGestureTime;
  final bool _gestureProtectionEnabled = true;
  double? _startDragY; // 拖拽开始位置
  static const Duration _gestureProtectionInterval = Duration(
    milliseconds: 500,
  );

  final Map<String, String> _streamingMessages = {};
  final Map<String, String> _streamingContent = {};
  final Map<String, int> _streamingVersions = {};
  final Map<String, Completer> _streamProcessingLocks = {};

  String get connectionStatus {
    switch (_connectionStatus) {
      case ConnectionStatus.connected:
        return 'connected';
      case ConnectionStatus.connecting:
        return 'connecting';
      case ConnectionStatus.reconnecting:
        return 'reconnecting';
      case ConnectionStatus.disconnected:
        return 'disconnected';
      case ConnectionStatus.configMissing:
        return 'config_missing';
    }
  }

  bool get isVoiceInputMode => _isVoiceInputMode;
  bool get isRecording => _isRecording;
  bool get isCancelling => _isCancelling;
  bool get isSoundPlaybackEnabled => _isSoundPlaybackEnabled;
  bool get hasText => _hasText;
  bool get isLoadingMore => _isLoadingMore;
  bool get isUserWaiting => _isUserWaiting;
  bool get isAssistantWaiting => _isAssistantWaiting;

  // 字体大小相关
  double? get fontSize => _fontSize;

  ChatProvider({
    required this.conversation,
    required this.conversationProvider,
    required this.diyServiceProvider,
    required this.configProvider,
    required this.context,
  }) {
    _init();
  }

  void _init() {
    WidgetsBinding.instance.addObserver(this);
    textController.addListener(_onTextChanged);
    scrollController.addListener(_onScroll);

    // 监听ConfigProvider变化
    configProvider.addListener(_onConfigChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // 加载字体大小设置
      final prefs = await SharedPreferences.getInstance();
      _fontSize = prefs.getDouble('chat_font_size_${conversation.id}');

      conversationProvider.markConversationAsRead(conversation.id);

      // 初始化音频系统（进入聊天页面时）
      await _initializeAudioSystem();

      // 在进入chat页面时检查网络权限（使用系统API）
      await _checkNetworkPermissionOnChatEnter();

      if (conversation.type == ConversationType.diy) {
        await _initDiyServiceFromProvider();
      } else if (conversation.type == ConversationType.dify) {
        _initDifyService();
      }
      _ensureScrollToBottom();
    });
  }

  /// 配置变更时的处理
  void _onConfigChanged() {
    if (conversation.type == ConversationType.diy) {
      final configId = conversation.configId;
      final configExists = configProvider.diyConfigs.any(
        (config) => config.id == configId,
      );

      if (!configExists &&
          _connectionStatus != ConnectionStatus.configMissing) {
        // 配置被删除，更新状态
        logW('检测到配置被删除: $configId');
        _connectionStatus = ConnectionStatus.configMissing;
        notifyListeners();
        _showConfigMissingDialog();
      } else if (configExists &&
          _connectionStatus == ConnectionStatus.configMissing) {
        // 配置已恢复，尝试重新连接
        logI('检测到配置已恢复，重新初始化连接');
        _initDiyServiceFromProvider();
      }
    }
  }

  /// 清理流式数据（公共方法）
  void _clearStreamingData() {
    _streamingMessages.clear();
    _streamingContent.clear();
    _streamingVersions.clear();
  }

  /// 清理STT流式数据，但保留已创建的用户消息
  void _clearSttStreamingData() {
    // 只清理STT相关的流式数据，保留其他流式数据
    final sttKeys =
        _streamingMessages.keys.where((key) => key.startsWith('stt_')).toList();
    for (final key in sttKeys) {
      _streamingMessages.remove(key);
      _streamingContent.remove(key);
      _streamingVersions.remove(key);
    }
  }

  @override
  void dispose() {
    logI('ChatProvider: Disposing...');
    _disposed = true; // 设置dispose标志，防止后续显示对话框
    WidgetsBinding.instance.removeObserver(this);
    configProvider.removeListener(_onConfigChanged);
    _serviceSubscription?.cancel();

    // 清理DiyServiceProvider中的缓存服务
    diyServiceProvider.disposeService(conversation.id);

    // 停止所有音频播放和录音
    _disposeAudioService();

    // 断开WebSocket连接
    if (_diyService != null) {
      _diyService!.disconnectWebSocket();
      logI('WebSocket connection disconnected on dispose');
    }

    // 清理展示资源
    scrollController.removeListener(_onScroll);
    textController.removeListener(_onTextChanged);
    textController.dispose();
    scrollController.dispose();
    textFocusNode.dispose();
    _clearStreamingData();

    // 重置状态
    _isUserWaiting = false;
    _isAssistantWaiting = false;
    _isVoiceInputMode = false;
    _isCancelling = false;
    _isRecording = false;
    _initialScrollPending = true;
    super.dispose();
  }

  /// 应用恢复时重新检查网络权限
  Future<void> _recheckNetworkPermissionOnResume() async {
    // 延迟一点时间，确保应用完全恢复
    await Future.delayed(Duration(milliseconds: 1000));

    // 简化：只检查WebSocket服务连接状态
    if (conversation.type == ConversationType.diy &&
        _diyService != null &&
        !_diyService!.isConnected) {
      logI('App resumed, attempting to reconnect to Diy service');
      await _attemptServiceReconnection();
    }
  }

  Future<void> _disposeAudioService() async {
    try {
      await AudioService.instance.disposeAllComponents();
    } catch (e) {
      logE('Error in _disposeAudioService: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.resumed:
        // 应用从后台返回前台
        logI('App resumed');

        // 重新检查网络权限
        _recheckNetworkPermissionOnResume();

        if (conversation.type == ConversationType.diy &&
            _diyService != null &&
            !_diyService!.isConnected) {
          logI('App resumed, attempting to reconnect to Diy service.');
          _diyService!.connectWebSocket();
        }
        Future.delayed(const Duration(milliseconds: 300), () {
          _ensureScrollToBottom();
        });
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.inactive:
        logI('App paused/detached/inactive, stopping audio playback');
        AudioService.instance.setPlaybackState(false);
        break;
      default:
        break;
    }
  }

  void _onScroll() {
    if (!scrollController.hasClients) {
      return;
    }

    final isAtBottom = scrollController.position.pixels <= _scrollThreshold;

    if (isAtBottom) {
      if (_userInteractedWithScroll) {
        _userInteractedWithScroll = false;
        notifyListeners();
      }
    } else {
      if (!_userInteractedWithScroll) {
        _userInteractedWithScroll = true;
        notifyListeners();
      }
    }
  }

  void _onTextChanged() {
    final hasText = textController.text.trim().isNotEmpty;
    if (_hasText != hasText) {
      _hasText = hasText;
      notifyListeners();
    }
  }

  /// 初始化音频系统（进入聊天页面时）
  Future<void> _initializeAudioSystem() async {
    try {
      logI('初始化音频系统（聊天模式）');

      // 使用AudioService统一初始化接口
      await AudioService.instance.initializeAudioService(mode: AudioMode.chat);
    } catch (e) {
      logE('音频系统初始化失败: $e');
    }
  }

  Future<void> _loadMuteState() async {
    final prefs = await SharedPreferences.getInstance();
    final storedMuteState = prefs.getBool('mute_${conversation.id}') ?? false;

    logI('加载静音状态: stored=$storedMuteState, current=$_isSoundPlaybackEnabled');

    // 确保UI状态一致
    _isSoundPlaybackEnabled = !storedMuteState;

    // 直接设置到正确状态，不使用toggle避免状态翻转问题
    _diyService?.setMute(storedMuteState);
    AudioService.instance.setMuteState(storedMuteState);

    // 清除可能的静音状态变更标记，确保新对话能正常播放
    if (!storedMuteState) {
      // 如果不是静音状态，确保AudioService中的静音状态变更标记被清除
      AudioService.instance.setCurrentRequestId(null);
    }

    logI('静音状态同步完成: muted=$storedMuteState, enabled=$_isSoundPlaybackEnabled');
    notifyListeners();
  }

  Future<void> _saveMuteState(bool isSoundEnabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('mute_${conversation.id}', !isSoundEnabled);
  }

  /// 进入chat页面时检查网络权限（简化版本）
  Future<void> _checkNetworkPermissionOnChatEnter() async {
    try {
      logI('进入chat页面时检查网络权限');
      // 简化：不进行复杂的网络权限检查，让系统自动处理
    } catch (e) {
      logE('进入chat页面时网络权限检查错误: $e');
    }
  }

  /// 检查网络权限并在需要时弹出系统授权对话框（简化版本）
  Future<void> _checkAndRequestNetworkPermission() async {
    try {
      logI('执行网络权限系统检查');
      // 简化：不进行复杂的网络权限检查，让系统自动处理
    } catch (e) {
      logE('网络权限系统检查错误: $e');
    }
  }

  /// 尝试重新连接服务
  Future<void> _attemptServiceReconnection() async {
    try {
      if (_diyService != null && !_diyService!.isConnected) {
        logI('Attempting to reconnect service after permission granted');
        _connectionStatus = ConnectionStatus.connecting;
        notifyListeners();

        // 移除重连时的底部提示，改用中间对话框
        _showConnectionErrorDialog('网络连接', '网络权限已授权，正在重新连接服务...');

        await _diyService!.connectWebSocket();
        logI('Service reconnection initiated successfully');
      } else if (_diyService == null) {
        // 如果服务还未初始化，重新初始化
        logI('Reinitializing service after permission granted');
        _showConnectionErrorDialog('服务初始化', '网络权限已授权，正在初始化服务...');
        await _initDiyServiceFromProvider();
      }
    } catch (e) {
      logE('Failed to reconnect service after permission granted: $e');
      _connectionStatus = ConnectionStatus.disconnected;
      notifyListeners();
      _showConnectionErrorDialog('服务重连失败', '服务重连失败，请稍后重试');
    }
  }

  /// 获取用于连通性检查的服务器地址
  String? _getServerUrlForConnectivityCheck() {
    try {
      // 如果是diy对话，获取配置的服务器地址
      if (conversation.type == ConversationType.diy) {
        final diyConfig = configProvider.selectedDiyConfig;
        if (diyConfig != null) {
          // 从WebSocket URL提取完整的健康检查地址
          String websocketUrl = diyConfig.websocketUrl;
          // 将 ws:// 或 wss:// 转换为 http:// 或 https://
          String httpUrl;
          if (websocketUrl.startsWith('ws://')) {
            httpUrl = websocketUrl.replaceFirst('ws://', 'http://');
          } else if (websocketUrl.startsWith('wss://')) {
            httpUrl = websocketUrl.replaceFirst('wss://', 'https://');
          } else {
            httpUrl = websocketUrl;
          }

          // 移除WebSocket路径部分，并添加完整的健康检查路径
          final uri = Uri.parse(httpUrl);
          final healthUrl =
              '${uri.scheme}://${uri.host}:${uri.port}/api/v1/health';
          return healthUrl;
        }
      }

      // 如果是dify对话，获取dify配置的API地址
      if (conversation.type == ConversationType.dify) {
        final difyConfig = configProvider.difyConfig;
        if (difyConfig != null) {
          return difyConfig.apiUrl;
        }
      }

      // 如果没有配置，返回默认的健康检查地址
      return 'http://localhost:8000/api/v1/health';
    } catch (e) {
      logE('Error getting server URL for connectivity check: $e');
      return null;
    }
  }

  /// 连接成功时的处理
  void _onConnectionSuccess() {
    // 关闭WebSocket连接相关的对话框
    if (_activeConnectionDialogContext != null) {
      try {
        Navigator.of(_activeConnectionDialogContext!).pop();
        logI('自动关闭连接错误对话框');
      } catch (e) {
        logE('关闭连接错误对话框失败: $e');
      }
      _activeConnectionDialogContext = null;
    }

    // 重置WebSocket连接错误对话框状态
    _isConnectionErrorDialogShown = false;

    logI('连接成功，重置连接错误对话框状态');
  }

  /// 用户手动关闭对话框的处理
  void _onUserDismissDialog(DialogType type) {
    switch (type) {
      case DialogType.connectionError:
        // 不重置 _isConnectionErrorDialogShown，阻止后续弹窗
        logI('用户手动关闭连接错误对话框');
        break;
    }
  }

  /// 对话框关闭后的处理
  void _onDialogClosed(DialogType type) {
    // 这里可以添加对话框关闭后的通用处理逻辑
    logI('对话框已关闭: $type');
  }

  /// 处理WebSocket断开连接事件
  Future<void> _handleWebSocketDisconnection() async {
    try {
      logI('处理WebSocket断开连接事件');

      // 检查是否已显示过连接错误对话框
      if (_isConnectionErrorDialogShown) {
        logI('连接错误对话框已显示，后台继续重连但不重复弹窗');
        // 后台继续重连，但不显示新的对话框
        return;
      }

      // 简化逻辑：WebSocket断开连接时只显示连接错误对话框
      // 不再进行网络权限检查，避免错误的权限推断

      final serverUrl = _getServerUrlForConnectivityCheck();
      if (serverUrl != null) {
        final client = HttpClient();
        client.connectionTimeout = Duration(seconds: 3);

        try {
          final request = await client.getUrl(Uri.parse(serverUrl));
          final response = await request.close();
          await response.drain();
          client.close();

          // 服务器可达，可能是服务问题
          logI('服务器可达，可能是服务临时不可用');
          _showConnectionErrorDialog('服务连接中断', '与服务器连接已断开，但服务器可达。可能是服务临时问题。');
          return;
        } catch (e) {
          client.close();

          // 服务器不可达，显示通用连接错误对话框
          // 不再区分是否是网络权限问题
          logI('服务器不可达，显示连接错误对话框');
          _showConnectionErrorDialog('服务连接失败', '无法连接服务器健康检查: $serverUrl。');
          return;
        }
      }

      // 如果无法获取服务器地址，显示通用连接错误
      _showConnectionErrorDialog('连接断开', '与服务器的连接已断开，请检查网络连接。');
    } catch (e) {
      logE('Error handling WebSocket disconnection: $e');
      // 错误处理本身失败时，显示通用错误对话框
      _showConnectionErrorDialog('连接错误', '连接发生错误，请稍后重试。');
    }
  }

  /// 手动重新检查网络权限状态（使用系统API）
  Future<void> recheckNetworkPermission() async {
    logI('手动重新检查网络权限状态');
    await _checkAndRequestNetworkPermission();
  }

  Future<void> _initDiyServiceFromProvider() async {
    // 检查配置是否存在
    final configId = conversation.configId;
    if (configId.isEmpty) {
      _connectionStatus = ConnectionStatus.configMissing;
      notifyListeners();
      _showConfigMissingDialog();
      return;
    }

    final configExists = configProvider.diyConfigs.any(
      (config) => config.id == configId,
    );

    if (!configExists) {
      logW('配置 $configId 不存在，标记为配置缺失');
      _connectionStatus = ConnectionStatus.configMissing;
      notifyListeners();
      _showConfigMissingDialog();
      return;
    }

    // 配置存在，继续正常连接
    _connectionStatus = ConnectionStatus.connecting;
    notifyListeners();

    try {
      logI('初始化服务器连接...');
      final service = await diyServiceProvider.getServiceForConversation(
        conversation,
      );
      _diyService = service;
      _serviceSubscription = _diyService!.listen(_onDiyServiceEvent);

      // 关键修复：订阅后立即检查服务连接状态
      // 如果服务已经连接（订阅前已连接），手动触发connected事件处理
      if (_diyService!.isConnected) {
        _onDiyServiceEvent({'type': 'connected', 'data': null});
      }

      await _loadMuteState();
      logI('服务器连接初始化完成');
    } catch (e) {
      logE('Failed to get service from provider: $e');
      _connectionStatus = ConnectionStatus.disconnected;
      notifyListeners();
      // 移除WebSocket连接失败时的底部SnackBar，改用中间对话框
      _showConnectionErrorDialog('获取服务失败', e.toString());
    }
  }

  Future<void> _initDifyService() async {
    final String configId = conversation.configId;
    DifyConfig? difyConfig;

    if (configId.isNotEmpty) {
      difyConfig =
          configProvider.difyConfigs
              .where((config) => config.id == configId)
              .firstOrNull;
    }

    if (difyConfig == null) {
      if (configProvider.difyConfigs.isEmpty) {
        _showCustomSnackbar("未设置Dify配置，请先在设置中配置Dify API");
        return;
      }
      difyConfig = configProvider.difyConfigs.first;
    }

    _difyService = await DifyService.create(
      apiKey: difyConfig.apiKey,
      apiUrl: difyConfig.apiUrl,
    );
  }

  void _onDiyServiceEvent(Map<String, dynamic> event) {
    try {
      final type = event['type'];
      final data = event['data'];
      logI('ChatProvider: Received event: $type');

      switch (type) {
        case 'connected':
          _connectionStatus = ConnectionStatus.connected;
          // 连接成功时重置所有对话框状态
          _onConnectionSuccess();
          // WebSocket连接建立后，根据配置优先级自动同步模型配置
          _syncModelConfigOnConnection();
          if (_initialScrollPending) {
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => _scrollToBottom(),
            );
          }
          break;
        case 'disconnected':
          _connectionStatus = ConnectionStatus.disconnected;
          // 在断开连接时进行统一的错误检查和处理
          _handleWebSocketDisconnection();
          break;
        case 'reconnecting':
          _connectionStatus = ConnectionStatus.reconnecting;
          break;
        case 'responseText':
          _handleStreamResponse(data);
          return;
        case 'userMessage':
          _handleUserMessage(data);
          // 用户直接输入文字，不设置等待气泡
          return;
        case 'ttsStart':
          return;
        case 'ttsStop':
          _cleanupStreamingState();
          return;
        case 'ttsEnd':
          _cleanupStreamingState();
          return;
        case 'stt':
          _handleSttResult(data);
          return;
        case 'error':
          logE('Service error: $data');
          // 统一使用连接错误弹窗，不再区分服务器错误和连接错误
          _showConnectionErrorDialog('服务连接错误', data.toString());
          break;
      }
      notifyListeners();
    } catch (e, s) {
      logE('Fatal Error in _onDiyServiceEvent: $e\n$s');
      _showCustomSnackbar('处理事件时发生严重错误: $e'); // 保留非连接错误的底部提示
    }
  }

  void _handleUserMessage(Object? data) async {
    String text;
    String sessionRequestId;

    // 支持两种数据格式：旧格式（直接文本）和新格式（包含session_request_id）
    if (data is String) {
      // 兼容旧格式
      text = data;
      sessionRequestId = '';
    } else if (data is Map<String, dynamic>) {
      // 新格式，包含session_request_id
      text = data['text'] as String;
      sessionRequestId = data['session_request_id'] as String? ?? '';
    } else {
      logE('Unexpected userMessage data type: ${data.runtimeType}');
      return;
    }

    if (text.isNotEmpty) {
      // 关键修复：为STT消息使用不同的键空间，避免与LLM消息冲突
      final streamKey =
          sessionRequestId.isNotEmpty
              ? 'stt_$sessionRequestId' // 为STT消息添加前缀，避免与LLM冲突
              : 'default_user_message';

      // 参考助手侧的流式处理机制，添加并发控制
      while (_streamProcessingLocks.containsKey(streamKey)) {
        await _streamProcessingLocks[streamKey]!.future;
      }

      final lockCompleter = Completer();
      _streamProcessingLocks[streamKey] = lockCompleter;

      try {
        if (!_streamingMessages.containsKey(streamKey)) {
          // 第一次收到消息，创建新的用户消息
          final messageId = await conversationProvider.addMessage(
            conversationId: conversation.id,
            role: MessageRole.user,
            content: text,
          );
          _streamingMessages[streamKey] = messageId;
          _streamingContent[streamKey] = text;
        } else {
          // 更新现有内容
          final currentContent = _streamingContent[streamKey] ?? '';
          // 只有当内容有变化时才更新消息（类似助手侧处理）
          if (text != currentContent || text.length > currentContent.length) {
            _streamingContent[streamKey] = text;
            final messageId = _streamingMessages[streamKey];
            if (messageId != null) {
              await conversationProvider.updateMessage(
                messageId: messageId,
                content: text,
              );
              _ensureScrollToBottom();
            }
          }
        }

        // 取消用户侧等待状态
        _isUserWaiting = false;
        notifyListeners();
      } finally {
        _streamProcessingLocks.remove(streamKey);
        lockCompleter.complete();
      }
    }
  }

  void _handleSttResult(Map<String, dynamic> data) {
    final text = data['text'] as String;
    final isFinal = data['is_final'] as bool;
    textController.text = text;

    if (text.isNotEmpty) {
      final messages = conversationProvider.getMessages(conversation.id);
      final lastMessage = messages.isNotEmpty ? messages.last : null;

      // 如果是第一个文本结果或者没有用户消息，创建新消息
      if (lastMessage == null || lastMessage.role != MessageRole.user) {
        // 创建用户消息
        conversationProvider.addMessage(
          conversationId: conversation.id,
          role: MessageRole.user,
          content: text,
        );
      } else {
        // 更新现有用户消息内容
        conversationProvider.updateMessage(
          messageId: lastMessage.id,
          content: text,
        );
      }

      // 收到STT结果后取消用户侧等待状态
      if (isFinal) {
        _isUserWaiting = false;
        notifyListeners();
      }

      // 如果是最终结果，停止录音
      if (isFinal) {
        stopRecording(cancelled: false);
      }
    }
  }

  Future<void> _handleStreamResponse(Map<String, dynamic> data) async {
    try {
      // 收到streamResponse时取消助手侧等待状态
      _isAssistantWaiting = false;
      notifyListeners();

      final String rawText = data['text'] ?? '';
      final String text = rawText.trim();
      final String sessionRequestId = data['session_request_id'] ?? '';
      final String sessionId = data['session_id'] ?? '';

      // 即使内容为空也要处理，以便更新占位符消息
      final String streamKey =
          sessionRequestId.isNotEmpty
              ? sessionRequestId
              : (sessionId.isNotEmpty ? sessionId : 'default_stream');

      // 关键修复：当LLM开始响应时，清理STT流式数据，避免消息冲突
      // 这确保用户消息不会被LLM消息覆盖
      _clearSttStreamingData();

      while (_streamProcessingLocks.containsKey(streamKey)) {
        await _streamProcessingLocks[streamKey]!.future;
      }

      final lockCompleter = Completer();
      _streamProcessingLocks[streamKey] = lockCompleter;

      try {
        if (!_streamingMessages.containsKey(streamKey)) {
          // 只有在有实际内容时才创建消息
          if (text.isNotEmpty) {
            final messageId = await conversationProvider.addMessage(
              conversationId: conversation.id,
              role: MessageRole.assistant,
              content: text,
              sessionResponseId:
                  streamKey == 'default_stream' ? null : streamKey,
            );
            _streamingMessages[streamKey] = messageId;
            _streamingContent[streamKey] = text;
          }
        } else {
          final currentContent = _streamingContent[streamKey] ?? '';
          // 如果内容有变化，就更新消息
          if (text.isNotEmpty &&
              (text != currentContent ||
                  text.length > currentContent.length ||
                  (text.length < currentContent.length &&
                      !currentContent.contains(text)))) {
            _streamingContent[streamKey] = text;
            final messageId = _streamingMessages[streamKey];
            if (messageId != null) {
              await conversationProvider.updateMessage(
                messageId: messageId,
                content: text,
              );
              _ensureScrollToBottom();
            }
          }
        }

        if (_diyService?.isMuted == true &&
            (_isUserWaiting || _isAssistantWaiting)) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _cleanupStreamingState(),
          );
        }
      } finally {
        _streamProcessingLocks.remove(streamKey);
        lockCompleter.complete();
      }
    } catch (e, s) {
      logE('Fatal Error in _handleStreamResponse: $e\n$s');
      _showCustomSnackbar('处理流式响应时发生严重错误: $e');
    }
  }

  void _cleanupStreamingState() {
    _clearStreamingData();
    _isUserWaiting = false;
    _isAssistantWaiting = false;
    notifyListeners();
  }

  Future<void> sendMessage() async {
    final text = textController.text.trim();
    if (text.isEmpty) {
      return;
    }

    // 清理之前的消息状态
    _clearStreamingData();

    // 先添加用户消息到界面
    await conversationProvider.addMessage(
      conversationId: conversation.id,
      role: MessageRole.user,
      content: text,
    );

    textController.clear();

    // 文字输入只设置助手侧等待气泡
    _isAssistantWaiting = true;

    // 关键修复：设置播放状态，准备接收TTS音频
    AudioService.instance.setPlaybackState(true);

    notifyListeners();

    try {
      if (conversation.type == ConversationType.diy) {
        _diyService?.sendTextMessage(text);
      } else if (conversation.type == ConversationType.dify) {
        await _sendDifyMessage(text);
      }
    } catch (e) {
      logE('Error sending message: $e');
      // 发送消息失败保留底部提示，因为这是用户操作相关的
      _showCustomSnackbar('发送消息失败: ${e.toString()}');

      // 发送出错时取消助手侧等待状态
      _isAssistantWaiting = false;
      notifyListeners();
    }
  }

  Future<void> _sendDifyMessage(String text) async {
    final isNewConversation = conversation.title == '新对话';
    await conversationProvider.addMessage(
      conversationId: conversation.id,
      role: MessageRole.user,
      content: text,
    );
    _forceScrollToBottom();

    try {
      final response = await _difyService!.sendMessage(
        text,
        sessionId: conversation.id,
      );
      await conversationProvider.addMessage(
        conversationId: conversation.id,
        role: MessageRole.assistant,
        content: response,
      );
    } finally {
      _isUserWaiting = false;
      _isAssistantWaiting = false;
      notifyListeners();
      _forceScrollToBottom();

      final messages = conversationProvider.getMessages(conversation.id);
      if (isNewConversation && messages.length > 1) {
        try {
          final title = await _difyService!.sendMessage(
            '请为我们的对话生成一个5个字以内的标题。',
            sessionId: conversation.id,
          );
          if (title.isNotEmpty) {
            await conversationProvider.updateConversationTitle(
              conversation.id,
              title,
            );
          }
        } catch (e) {
          logE('Failed to generate conversation title: $e');
        }
      }
    }
  }

  Future<void> startRecording() async {
    // 检查是否是自定义服务对话
    if (conversation.type != ConversationType.diy || _diyService == null) {
      _showCustomSnackbar('语音功能仅适用于自定义服务对话');
      _isVoiceInputMode = false;
      notifyListeners();
      return;
    }

    try {
      // 设置录音准备状态，UI显示录音动画但不震动
      _isRecording = true;

      // 停止上一次播放
      AudioService.instance.setPlaybackState(false);
      // await AudioService.instance.stopPlaybackAudio();
      await Future.delayed(const Duration(milliseconds: 200));

      // 清理未完成的流式数据
      _clearStreamingData();

      // 开始录音
      await _diyService!.startRecording();

      // 触发震动
      HapticFeedback.mediumImpact();
      notifyListeners();
    } catch (e) {
      logE('开始录音失败: $e');
      _showCustomSnackbar('无法开始录音: ${e.toString()}');
      _isRecording = false;
      _isVoiceInputMode = false;
      notifyListeners();
    }
  }

  Future<void> stopRecording({bool cancelled = false}) async {
    if (!_isRecording) {
      return;
    }

    try {
      logI('语音输入结束，准备发送音频数据');

      // 1. 立即设置录音状态，防止重复触发
      _isRecording = false;
      notifyListeners();

      if (cancelled) {
        // 取消录音
        if (_diyService != null) {
          try {
            await _diyService!.cancelStopRecording();
            logI('已取消录音');
          } catch (e) {
            logE('取消录音失败: $e');
          }
        }
        textController.clear();
      } else {
        // 正常结束录音
        if (_diyService != null) {
          try {
            await _diyService!.stopRecording();
            logI('已停止录音');
          } catch (e) {
            logE('停止录音失败: $e');
          }
        }

        // 正常停止录音时设置等待状态
        _isUserWaiting = true;
        _isAssistantWaiting = true;
        notifyListeners();

        // 震动反馈
        HapticFeedback.mediumImpact();

        // 如果当前是静音状态，设置超时保护
        if (_diyService?.isMuted == true) {
          logI('静音状态下的语音输入，设置超时保护');
          Timer(const Duration(seconds: 5), () {
            if ((_isUserWaiting || _isAssistantWaiting) &&
                _diyService?.isMuted == true) {
              logI('静音状态超时，结束加载状态');
              _isUserWaiting = false;
              _isAssistantWaiting = false;
              notifyListeners();
            }
          });
        }
      }
    } catch (e) {
      logE('停止录音失败: $e');
      _showCustomSnackbar('录音处理失败: ${e.toString()}');
      _isRecording = false;

      // 录音出错时取消等待状态
      _isUserWaiting = false;
      _isAssistantWaiting = false;
      notifyListeners();
    }
  }

  Future<void> toggleMute() async {
    // 要设置的新静音状态
    final newMuteState = _isSoundPlaybackEnabled;

    logI(
      '切换静音状态: currentEnabled=$_isSoundPlaybackEnabled, newMuted=$newMuteState',
    );
    // 取消静音 - 恢复播放
    _diyService?.setMute(newMuteState);

    // 如果是静音状态，清理流式数据并中断播放
    if (newMuteState) {
      // 清理流式数据
      _cleanupStreamingState();
      // 中断播放器播放
      AudioService.instance.setPlaybackState(false);
    }

    // 发送静音事件同步后端
    _diyService?.sendMuteEvent(newMuteState);

    // 保存静音状态并持久化
    _isSoundPlaybackEnabled = !newMuteState;
    _saveMuteState(_isSoundPlaybackEnabled);

    logI('静音状态切换完成: muted=$newMuteState');
    notifyListeners();
  }

  void toggleInputMode() {
    _isVoiceInputMode = !_isVoiceInputMode;
    if (_isVoiceInputMode) {
      textFocusNode.unfocus();
    } else {
      textFocusNode.requestFocus();
    }
    notifyListeners();
  }

  void resetConversation() {
    conversationProvider.clearMessages(conversation.id);
    if (conversation.type == ConversationType.dify) {
      // _difyService?.resetConversation(); // This method does not exist yet, but we can add it later if needed.
    }
    _showCustomSnackbar('新对话已开始');
  }

  void scrollToBottom({bool force = false}) {
    if (!scrollController.hasClients) {
      return;
    }

    if (_userInteractedWithScroll && !force) {
      return;
    }

    // Ensure we are not in the middle of a build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scrollController.hasClients) {
        scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });

    _initialScrollPending = false;
  }

  void _scrollToBottom() {
    if (scrollController.hasClients) {
      scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
    _initialScrollPending = false;
  }

  void _forceScrollToBottom() {
    if (scrollController.hasClients) {
      scrollController.jumpTo(0.0);
    }
  }

  void _ensureScrollToBottom() {
    if (_initialScrollPending || !_userInteractedWithScroll) {
      _scrollToBottom();
    }
  }

  void navigateToTelephony() {
    if (_diyService == null ||
        _diyService!.webSocketManager == null ||
        _diyService!.sessionId == null ||
        _diyService!.sessionId!.isEmpty) {
      _showCustomSnackbar('服务未连接或会话ID无效，无法进行语音通话');
      return;
    }

    // 使用与 DiyService 相同的配置源（通过 conversation.configId 查找）
    final configId = conversation.configId;
    if (configId.isEmpty) {
      _showCustomSnackbar('对话配置ID为空');
      return;
    }

    final diyConfig = configProvider.diyConfigs
        .whereType<DiyConfig>()
        .firstWhere(
          (config) => config.id == configId,
          orElse: () => throw Exception("DiyConfig ID '$configId' not found."),
        );

    // URL 转换 ws:// → http://
    String websocketUrl = diyConfig.websocketUrl;
    String httpUrl =
        websocketUrl.startsWith('ws://')
            ? websocketUrl.replaceFirst('ws://', 'http://')
            : websocketUrl.replaceFirst('wss://', 'https://');

    // 提取基础地址
    final uri = Uri.parse(httpUrl);
    String serverUrl = '${uri.scheme}://${uri.host}:${uri.port}';

    // 添加验证日志
    logI('🔗 Telephony 地址同步: WebSocket=$websocketUrl, WebRTC=$serverUrl');

    unawaited(
      Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder:
              (context, animation, secondaryAnimation) => TelephonyScreen(
                webSocketManager: _diyService!.webSocketManager!,
                sessionId: _diyService!.sessionId!,
                serverUrl: serverUrl,
              ),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        ),
      ),
    );
  }

  /// 设置字体大小
  Future<void> setFontSize(double fontSize) async {
    _fontSize = fontSize;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('chat_font_size_${conversation.id}', fontSize);
    notifyListeners();
  }

  /// 重新加载字体大小（从 SharedPreferences）
  Future<void> reloadFontSize() async {
    final prefs = await SharedPreferences.getInstance();
    final newFontSize = prefs.getDouble('chat_font_size_${conversation.id}');
    if (newFontSize != null && newFontSize != _fontSize) {
      _fontSize = newFontSize;
      notifyListeners();
    }
  }

  // 新增：处理应用生命周期变化
  void handleAppLifecycleChange(AppLifecycleState state) {
    didChangeAppLifecycleState(state);
  }

  // 新增：设置用户滚动交互状态
  void setUserInteractedWithScroll(bool value) {
    if (_userInteractedWithScroll != value) {
      _userInteractedWithScroll = value;
      notifyListeners();
    }
  }

  // 新增：加载更多消息
  Future<void> loadMoreMessages() async {
    if (_isLoadingMore) {
      return;
    }

    _isLoadingMore = true;
    notifyListeners();

    try {
      // 这里可以实现加载历史消息的逻辑
      await Future.delayed(const Duration(seconds: 1)); // 模拟加载
      logI('加载更多消息完成');
    } catch (e) {
      logE('加载更多消息失败: $e');
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  // 新增：语音输入手势处理
  void handleVoicePanStart(Object? details) {
    if (!_gestureProtectionEnabled) {
      return;
    }

    final now = DateTime.now();
    if (_lastGestureTime != null &&
        now.difference(_lastGestureTime!) < _gestureProtectionInterval) {
      return;
    }
    _lastGestureTime = now;

    // 支持两种类型的details参数
    final double startY;
    if (details is DragStartDetails) {
      startY = details.globalPosition.dy;
    } else if (details is LongPressStartDetails) {
      startY = details.globalPosition.dy;
    } else {
      return; // 不支持的类型
    }

    _startDragY = startY;
    _isCancelling = false;
    notifyListeners();
  }

  void handleVoicePanUpdate(Object? details) {
    if (!_isRecording) {
      return;
    }

    // 支持两种类型的details参数
    final double currentY;
    if (details is DragUpdateDetails) {
      currentY = details.globalPosition.dy;
    } else if (details is LongPressMoveUpdateDetails) {
      currentY = details.globalPosition.dy;
    } else {
      return; // 不支持的类型
    }

    final deltaY = (_startDragY ?? 0) - currentY;
    final shouldCancel = deltaY > _cancelThreshold;
    if (_isCancelling != shouldCancel) {
      _isCancelling = shouldCancel;
      notifyListeners();
    }
  }

  void handleVoicePanEnd(Object? details) {
    if (!_isRecording) {
      return;
    }

    if (_isCancelling) {
      stopRecording(cancelled: true);
    } else {
      stopRecording(cancelled: false);
    }

    _isCancelling = false;
    notifyListeners();
  }

  // 新增：图片选择功能
  Future<void> pickImage(ImageSource source) async {
    // 检查并请求相机/相册权限
    Permission permission =
        source == ImageSource.camera ? Permission.camera : Permission.photos;
    var status = await permission.status;
    if (status.isDenied) {
      status = await permission.request();
    }

    if (status.isPermanentlyDenied) {
      _showCustomSnackbar(
        '${source == ImageSource.camera ? "相机" : "相册"}权限被永久拒绝，请在系统设置中开启',
      );
      return;
    }

    if (!status.isGranted) {
      _showCustomSnackbar(
        '需要${source == ImageSource.camera ? "相机" : "相册"}权限才能选择图片',
      );
      return;
    }

    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (image != null) {
        // 添加图片消息
        await conversationProvider.addMessage(
          conversationId: conversation.id,
          role: MessageRole.user,
          content: '[图片]',
          imageLocalPath: image.path,
        );

        _forceScrollToBottom();
        logI('图片已添加: ${image.path}');
      }
    } catch (e) {
      logE('选择图片失败: $e');
      _showCustomSnackbar('选择图片失败: ${e.toString()}');
    }
  }

  void _showCustomSnackbar(String message) {
    // 检查是否已dispose
    if (_disposed) {
      logI('ChatProvider已dispose，跳过显示SnackBar');
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 1)),
    );
  }

  /// 显示连接错误对话框（统一处理WebSocket连接问题）
  void _showConnectionErrorDialog(String title, String message) {
    // 检查是否已dispose
    if (_disposed) {
      logI('ChatProvider已dispose，跳过显示对话框');
      return;
    }

    // 检查是否已显示过连接错误对话框
    if (_isConnectionErrorDialogShown) {
      logI('连接错误对话框已显示，跳过重复显示');
      return;
    }

    logI('显示连接错误对话框: $title - $message');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        // 保存Dialog上下文引用，用于后续自动关闭
        _activeConnectionDialogContext = dialogContext;

        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(Icons.wifi_off, color: Colors.orange, size: 24),
              SizedBox(width: 12),
              Text(
                title,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message,
                style: TextStyle(fontSize: 16, color: Colors.grey[700]),
              ),
              SizedBox(height: 12),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Text(
                  '请检查服务器是否启动或者手机网络是否正常。',
                  style: TextStyle(fontSize: 14, color: Colors.blue[800]),
                ),
              ),
            ],
          ),
          actions: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    _onUserDismissDialog(DialogType.connectionError);
                    _activeConnectionDialogContext = null; // 清理上下文引用
                    logI('用户点击"我知道了"关闭连接错误对话框');
                  },
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                  child: Text(
                    '我知道了',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    _onUserDismissDialog(DialogType.connectionError);
                    _activeConnectionDialogContext = null; // 清理上下文引用
                    logI('用户点击"重新连接"按钮');
                    // 重新尝试连接
                    _attemptReconnection();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                  child: Text('重新连接'),
                ),
              ],
            ),
          ],
        );
      },
    ).then((_) {
      _activeConnectionDialogContext = null; // 确保清理上下文引用
      _onDialogClosed(DialogType.connectionError);
    });

    // 设置状态，防止重复弹窗
    _isConnectionErrorDialogShown = true;
  }

  /// 用户点击重新连接按钮的处理
  Future<void> _attemptReconnection() async {
    try {
      logI('用户触发的重新连接开始');

      // 重置连接状态，允许在重连失败时显示新弹窗
      _isConnectionErrorDialogShown = false;

      if (_diyService != null) {
        // 如果服务已存在，直接尝试重新连接WebSocket
        _connectionStatus = ConnectionStatus.connecting;
        notifyListeners();
        await _diyService!.connectWebSocket();
      } else {
        // 如果服务未初始化，重新初始化服务
        await _initDiyServiceFromProvider();
      }

      logI('用户触发的重新连接完成');
    } catch (e) {
      logE('用户触发的重新连接失败: $e');
      _connectionStatus = ConnectionStatus.disconnected;
      notifyListeners();
    }
  }

  /// 显示配置缺失对话框
  void _showConfigMissingDialog() {
    // 检查是否已dispose
    if (_disposed) {
      logI('ChatProvider已dispose，跳过显示对话框');
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue, size: 24),
              SizedBox(width: 12),
              Text(
                '缺少服务配置',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '当前对话使用的服务器配置已被删除。',
                style: TextStyle(fontSize: 16, color: Colors.grey[700]),
              ),
              SizedBox(height: 12),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Text(
                  '请点击顶部标题进入设置，重新选择服务器配置。',
                  style: TextStyle(fontSize: 14, color: Colors.blue[800]),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text('我知道了'),
            ),
          ],
        );
      },
    );
  }

  /// WebSocket连接建立后，根据配置优先级自动同步模型配置
  ///
  /// 配置优先级逻辑：
  /// 1. 如果会话有自定义配置（sessionModelConfig != null 且不为空），使用会话配置
  /// 2. 如果会话无自定义配置，使用服务器配置（ServerModelConfig）
  /// 3. 如果都没有，跳过配置同步（使用服务器默认）
  void _syncModelConfigOnConnection() {
    if (_diyService == null) {
      logW('DiyService未初始化，跳过配置同步');
      return;
    }

    final sessionId = _diyService!.sessionId;
    if (sessionId == null || sessionId.isEmpty) {
      logW('Session ID为空，跳过配置同步');
      return;
    }

    // 1. 获取会话配置
    final sessionConfig = conversation.sessionModelConfig;

    // 2. 决定使用哪个配置
    Map<String, dynamic>? modelConfigToSync;

    if (sessionConfig != null && sessionConfig.selectedModels.isNotEmpty) {
      // 有会话配置 → 使用会话配置（用户自定义）
      modelConfigToSync = sessionConfig.selectedModels.cast<String, dynamic>();
      logI('🔄 使用会话级别模型配置: $modelConfigToSync');
    } else {
      // 无会话配置 → 使用服务器配置（新对话或未自定义）
      final serverConfig = configProvider.getModelConfig(conversation.configId);
      if (serverConfig != null && serverConfig.selectedModels.isNotEmpty) {
        modelConfigToSync = serverConfig.selectedModels.cast<String, dynamic>();
        logI('🔄 使用服务器级别模型配置: $modelConfigToSync');
      } else {
        logI('ℹ️ 无可用模型配置，将使用服务器默认配置');
        // 没有配置就不发送，使用服务器默认
        return;
      }
    }

    // 3. 发送配置到后端
    try {
      _diyService!.webSocketManager?.sendConfigRequest(
        sessionId: sessionId,
        modelConfig: modelConfigToSync!,
        requestId: IdGenerator.generateUniqueId(type: 'config'),
      );
      logI('✅ 配置已同步到后端: sessionId=$sessionId, config=$modelConfigToSync');
    } catch (e) {
      logE('❌ 配置同步失败: $e');
    }
  }
}
