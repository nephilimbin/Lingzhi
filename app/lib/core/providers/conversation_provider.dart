import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:ai_assistant/core/models/conversation.dart';
import 'package:ai_assistant/core/models/message.dart';
import 'package:ai_assistant/core/models/session_model_config.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ai_assistant/core/utils/app_logger.dart';

class ConversationProvider extends ChangeNotifier {
  List<Conversation> _conversations = [];
  final Map<String, List<Message>> _messages = {};

  // 添加分页相关参数
  static const int defaultPageSize = 30; // 每页加载的消息数量
  final Map<String, int> _loadedMessageCounts = {}; // 每个会话已加载的消息数量
  final Map<String, bool> _hasMoreMessages = {}; // 每个会话是否还有更多消息

  // 保存最后删除的会话及其消息，用于撤销删除
  Conversation? _lastDeletedConversation;
  List<Message>? _lastDeletedMessages;

  List<Conversation> get conversations => _conversations;
  List<Conversation> get pinnedConversations =>
      _conversations.where((conv) => conv.isPinned).toList();
  List<Conversation> get unpinnedConversations =>
      _conversations.where((conv) => !conv.isPinned).toList();

  ConversationProvider() {
    _loadConversations();
  }

  Future<void> _loadConversations() async {
    final prefs = await SharedPreferences.getInstance();

    // Load conversations
    final conversationsJson = prefs.getStringList('conversations') ?? [];
    _conversations =
        conversationsJson
            .map((json) => Conversation.fromJson(jsonDecode(json)))
            .toList();

    // 🔍 验证加载的conversations中的Session ID
    for (int i = 0; i < _conversations.length; i++) {
      final conv = _conversations[i];
      if (conv.diySessionId != null && conv.diySessionId!.isNotEmpty) {
        logI('✅ Conversation[$i] 有效的Session ID: ${conv.diySessionId}');
      } else {
        logW('⚠️ Conversation[$i] 没有Session ID或为空');
      }
    }

    // Load messages for each conversation
    for (final conversation in _conversations) {
      final messagesJson =
          prefs.getStringList('messages_${conversation.id}') ?? [];

      try {
        _messages[conversation.id] =
            messagesJson.map((json) {
              final decoded = jsonDecode(json);
              return Message.fromJson(decoded);
            }).toList();

        // 打印图片消息的信息
        for (final message in _messages[conversation.id] ?? []) {
          if (message.isImage) {
            // 检查图片文件是否存在
            if (message.imageLocalPath != null) {
              final imageFile = File(message.imageLocalPath!);
              final exists = await imageFile.exists();
              if (!exists) {
                logE('警告：图片文件不存在: ${message.imageLocalPath}');
              }
            }
          }
        }

        // 确保每个会话的图片目录存在
        final appDir = await getApplicationDocumentsDirectory();
        final conversationDir = Directory(
          '${appDir.path}/conversations/${conversation.id}/images',
        );
        if (!await conversationDir.exists()) {
          await conversationDir.create(recursive: true);
        }
      } catch (e, stackTrace) {
        logE('加载会话 ${conversation.id} 的消息时出错: $e');
        logE('堆栈跟踪: $stackTrace');
        // 如果某个会话的消息加载失败，继续加载其他会话
        _messages[conversation.id] = [];
      }
    }

    notifyListeners();
  }

  Future<void> _saveConversations() async {
    final prefs = await SharedPreferences.getInstance();

    // Save conversations
    final conversationsJson =
        _conversations
            .map((conversation) => jsonEncode(conversation.toJson()))
            .toList();
    await prefs.setStringList('conversations', conversationsJson);

    // Save messages for each conversation
    for (final entry in _messages.entries) {
      final messagesJson =
          entry.value.map((message) => jsonEncode(message.toJson())).toList();
      await prefs.setStringList('messages_${entry.key}', messagesJson);

      // 打印图片消息的信息
      for (final message in entry.value) {
        if (message.isImage) {}
      }
    }
  }

  Future<Conversation> createConversation({
    required String title,
    required ConversationType type,
    String configId = '',
  }) async {
    final uuid = const Uuid();
    final conversationId = uuid.v4();

    final newConversation = Conversation(
      id: conversationId,
      title: title,
      type: type,
      configId: configId,
      lastMessageTime: DateTime.now(),
      lastMessage: '',
      unreadCount: 0,
      isPinned: false,
    );

    _conversations.add(newConversation);
    _messages[newConversation.id] = [];

    await _saveConversations();
    notifyListeners();

    logI('创建新会话，ID = $conversationId');
    return newConversation;
  }

  Future<void> deleteConversation(String id) async {
    // 寻找要删除的会话
    final conversationIndex = _conversations.indexWhere(
      (conversation) => conversation.id == id,
    );

    if (conversationIndex != -1) {
      // 保存最后删除的会话和消息用于恢复
      _lastDeletedConversation = _conversations[conversationIndex];
      _lastDeletedMessages = _messages[id]?.toList();

      // 清理图片文件和音频文件
      try {
        final appDir = await getApplicationDocumentsDirectory();
        final conversationDir = Directory('${appDir.path}/conversations/$id');

        // 删除会话相关的图片和音频文件
        if (await conversationDir.exists()) {
          await conversationDir.delete(recursive: true);
          logI('已清理会话相关的图片文件: ${conversationDir.path}');
        }
      } catch (e) {
        logE('清理文件失败: $e');
      }

      // 从列表中移除
      _conversations.removeAt(conversationIndex);
      _messages.remove(id);

      await _saveConversations();
      notifyListeners();
    }
  }

  /// 根据ID获取对话
  Conversation? getConversationById(String id) {
    try {
      final conversation = _conversations.firstWhere((conv) => conv.id == id);
      logI(
        '🔍 找到conversation: id=$id, diySessionId=${conversation.diySessionId}',
      );
      return conversation;
    } catch (e) {
      logW('⚠️ 未找到conversation: id=$id');
      return null;
    }
  }

  // 恢复最后删除的会话
  Future<void> restoreLastDeletedConversation() async {
    if (_lastDeletedConversation != null) {
      // 恢复图片文件
      if (_lastDeletedMessages != null) {
        for (final message in _lastDeletedMessages!) {
          if (message.isImage && message.imageLocalPath != null) {
            try {
              final imageFile = File(message.imageLocalPath!);
              if (!await imageFile.parent.exists()) {
                await imageFile.parent.create(recursive: true);
              }
              // 如果文件不存在，说明已被删除，无法恢复
              logW('注意：图片文件 ${message.imageLocalPath} 已被删除，无法恢复');
            } catch (e) {
              logE('恢复图片文件失败: $e');
            }
          }
        }
      }

      _conversations.add(_lastDeletedConversation!);
      if (_lastDeletedMessages != null) {
        _messages[_lastDeletedConversation!.id] = _lastDeletedMessages!;
      } else {
        _messages[_lastDeletedConversation!.id] = [];
      }

      // 重置删除记录
      _lastDeletedConversation = null;
      _lastDeletedMessages = null;

      await _saveConversations();
      notifyListeners();
    }
  }

  Future<void> togglePinConversation(String id) async {
    final index = _conversations.indexWhere(
      (conversation) => conversation.id == id,
    );
    if (index != -1) {
      final updatedConversation = _conversations[index].copyWith(
        isPinned: !_conversations[index].isPinned,
      );
      _conversations[index] = updatedConversation;

      await _saveConversations();
      notifyListeners();
    }
  }

  Future<void> updateConversationTitle(
    String conversationId,
    String newTitle,
  ) async {
    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index != -1) {
      _conversations[index] = _conversations[index].copyWith(title: newTitle);
      await _saveConversations();
      notifyListeners();
    }
  }

  List<Message> getMessages(String conversationId) {
    return _messages[conversationId] ?? [];
  }

  // 新增：获取分页消息（最新的消息）
  List<Message> getLatestMessages(
    String conversationId, {
    int pageSize = defaultPageSize,
  }) {
    final allMessages = _messages[conversationId] ?? [];
    if (allMessages.isEmpty) {
      _loadedMessageCounts[conversationId] = 0;
      _hasMoreMessages[conversationId] = false;
      return [];
    }

    // 按时间戳排序，最新的在最后
    final sortedMessages = List<Message>.from(allMessages);
    sortedMessages.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    // 取最新的 pageSize 条消息
    final startIndex = math.max(0, sortedMessages.length - pageSize).toInt();
    final latestMessages = sortedMessages.sublist(startIndex);

    _loadedMessageCounts[conversationId] = latestMessages.length;
    _hasMoreMessages[conversationId] = startIndex > 0;

    return latestMessages;
  }

  // 新增：加载更多历史消息
  List<Message> loadMoreMessages(
    String conversationId, {
    int pageSize = defaultPageSize,
  }) {
    final allMessages = _messages[conversationId] ?? [];
    if (allMessages.isEmpty) {
      return [];
    }

    // 按时间戳排序，最新的在最后
    final sortedMessages = List<Message>.from(allMessages);
    sortedMessages.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    // 获取当前已加载的消息数量
    final currentLoadedCount = _loadedMessageCounts[conversationId] ?? 0;
    final totalCount = sortedMessages.length;

    if (currentLoadedCount >= totalCount) {
      _hasMoreMessages[conversationId] = false;
      return sortedMessages; // 返回所有消息
    }

    // 计算新的加载数量
    final newLoadCount = math.min(currentLoadedCount + pageSize, totalCount);
    final startIndex = totalCount - newLoadCount;
    final messagesWithMore = sortedMessages.sublist(startIndex);

    _loadedMessageCounts[conversationId] = messagesWithMore.length;
    _hasMoreMessages[conversationId] = startIndex > 0;

    return messagesWithMore;
  }

  // 新增：检查是否还有更多消息
  bool hasMoreMessages(String conversationId) {
    return _hasMoreMessages[conversationId] ?? false;
  }

  // 新增：重置分页状态（当有新消息时调用）
  void resetPaginationState(String conversationId) {
    _loadedMessageCounts.remove(conversationId);
    _hasMoreMessages.remove(conversationId);
  }

  Future<String> addMessage({
    required String conversationId,
    required MessageRole role,
    required String content,
    String? id,
    bool isImage = false,
    String? imageLocalPath,
    String? fileId,
    String? sessionResponseId,
  }) async {
    final messageId = id ?? const Uuid().v4();

    // 如果是图片消息，确保目录存在
    if (isImage && imageLocalPath != null) {
      try {
        final appDir = await getApplicationDocumentsDirectory();
        final conversationDir = Directory(
          '${appDir.path}/conversations/$conversationId/images',
        );
        if (!await conversationDir.exists()) {
          await conversationDir.create(recursive: true);
        }

        // 检查图片文件是否存在
        final imageFile = File(imageLocalPath);
        if (!await imageFile.exists()) {
          logI('警告：添加图片消息时文件不存在: $imageLocalPath');
        }
      } catch (e) {
        logE('创建图片目录失败: $e');
      }
    }

    final newMessage = Message(
      id: messageId,
      conversationId: conversationId,
      role: role,
      content: content,
      timestamp: DateTime.now(),
      isRead: role == MessageRole.user,
      isImage: isImage,
      imageLocalPath: imageLocalPath,
      fileId: fileId,
      sessionResponseId: sessionResponseId,
    );

    _messages[conversationId] = [
      ...(_messages[conversationId] ?? []),
      newMessage,
    ];

    // 添加新消息时重置分页状态，确保能看到最新消息
    resetPaginationState(conversationId);

    // Update conversation last message
    final index = _conversations.indexWhere(
      (conversation) => conversation.id == conversationId,
    );
    if (index != -1) {
      final updatedConversation = _conversations[index].copyWith(
        lastMessage: content,
        lastMessageTime: DateTime.now(),
        unreadCount:
            role == MessageRole.assistant
                ? _conversations[index].unreadCount + 1
                : _conversations[index].unreadCount,
      );
      _conversations[index] = updatedConversation;
    }

    await _saveConversations();
    notifyListeners();

    return messageId;
  }

  // 更新最后一条用户消息，用于图片上传后更新fileId等信息
  Future<void> updateLastUserMessage({
    required String conversationId,
    required String content,
    bool isImage = false,
    String? imageLocalPath,
    String? fileId,
  }) async {
    if (!_messages.containsKey(conversationId) ||
        _messages[conversationId]!.isEmpty) {
      logW('警告：找不到会话 $conversationId 或会话为空');
      return;
    }

    // 找到最后一条用户消息
    final messages = _messages[conversationId]!;
    int lastUserMessageIndex = -1;

    // 从后向前找最后一条用户消息
    for (int i = messages.length - 1; i >= 0; i--) {
      if (messages[i].role == MessageRole.user) {
        lastUserMessageIndex = i;
        break;
      }
    }

    // 如果找到了用户消息，则更新它
    if (lastUserMessageIndex != -1) {
      final oldMessage = messages[lastUserMessageIndex];

      // 如果是图片消息，保留原有的图片相关字段
      final updatedMessage = Message(
        id: oldMessage.id,
        conversationId: oldMessage.conversationId,
        role: oldMessage.role,
        content: content,
        timestamp: oldMessage.timestamp,
        isRead: oldMessage.isRead,
        isImage: isImage || oldMessage.isImage,
        imageLocalPath: imageLocalPath ?? oldMessage.imageLocalPath,
        fileId: fileId ?? oldMessage.fileId,
        sessionResponseId: oldMessage.sessionResponseId,
      );

      // 替换消息
      _messages[conversationId]![lastUserMessageIndex] = updatedMessage;

      // 如果这是最后一条消息，也更新会话的lastMessage
      if (lastUserMessageIndex == messages.length - 1) {
        final conversationIndex = _conversations.indexWhere(
          (conversation) => conversation.id == conversationId,
        );

        if (conversationIndex != -1) {
          final updatedConversation = _conversations[conversationIndex]
              .copyWith(lastMessage: content);
          _conversations[conversationIndex] = updatedConversation;
        }
      }

      await _saveConversations();
      notifyListeners();
    } else {
      logW('警告：在会话 $conversationId 中找不到用户消息');
    }
  }

  Future<void> updateMessage({
    required String messageId,
    required String content,
  }) async {
    // 查找包含该消息的会话
    String? targetConversationId;
    int messageIndex = -1;

    for (final entry in _messages.entries) {
      final index = entry.value.indexWhere(
        (message) => message.id == messageId,
      );
      if (index != -1) {
        targetConversationId = entry.key;
        messageIndex = index;
        break;
      }
    }

    if (targetConversationId != null && messageIndex != -1) {
      // 更新消息内容
      final oldMessage = _messages[targetConversationId]![messageIndex];
      final updatedMessage = Message(
        id: oldMessage.id,
        conversationId: oldMessage.conversationId,
        role: oldMessage.role,
        content: content,
        timestamp: oldMessage.timestamp,
        isRead: oldMessage.isRead,
        isImage: oldMessage.isImage,
        imageLocalPath: oldMessage.imageLocalPath,
        fileId: oldMessage.fileId,
        sessionResponseId: oldMessage.sessionResponseId,
      );

      _messages[targetConversationId]![messageIndex] = updatedMessage;

      // 更新会话的最后一条消息
      final conversationIndex = _conversations.indexWhere(
        (conversation) => conversation.id == targetConversationId,
      );

      if (conversationIndex != -1) {
        final updatedConversation = _conversations[conversationIndex].copyWith(
          lastMessage: content,
        );
        _conversations[conversationIndex] = updatedConversation;
      }

      await _saveConversations();
      notifyListeners();
    } else {
      logW('警告：找不到消息 $messageId');
    }
  }

  Future<void> markConversationAsRead(String conversationId) async {
    final index = _conversations.indexWhere(
      (conversation) => conversation.id == conversationId,
    );
    if (index != -1) {
      final updatedConversation = _conversations[index].copyWith(
        unreadCount: 0,
      );
      _conversations[index] = updatedConversation;

      // Mark all messages as read
      if (_messages.containsKey(conversationId)) {
        _messages[conversationId] =
            _messages[conversationId]!.map((message) {
              return Message(
                id: message.id,
                conversationId: message.conversationId,
                role: message.role,
                content: message.content,
                timestamp: message.timestamp,
                isRead: true,
                isImage: message.isImage,
                imageLocalPath: message.imageLocalPath,
                fileId: message.fileId,
                sessionResponseId: message.sessionResponseId,
              );
            }).toList();
      }

      await _saveConversations();
      notifyListeners();
    }
  }

  // 新增方法：更新自定义会话ID
  Future<void> updateDiySessionId(
    String conversationId,
    String? diySessionId,
  ) async {
    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index == -1) {
      logW('❌ 未找到对话: conversationId=$conversationId');
      return;
    }

    final oldSessionId = _conversations[index].diySessionId;

    // 只有当传入的 sessionId 不为 null 且原有的 sessionId 为 null 时才更新
    final shouldUpdate = diySessionId != null && oldSessionId == null;

    if (shouldUpdate) {
      logI(
        '✅ 需要更新 diySessionId: conversationId=$conversationId, $oldSessionId → $diySessionId',
      );

      try {
        _conversations[index] = _conversations[index].copyWith(
          diySessionId: diySessionId,
        );

        // 立即持久化到本地存储
        await _saveConversations();

        // 通知监听器状态变更
        notifyListeners();

        logI(
          '🎉 成功更新并持久化 diySessionId: conversationId=$conversationId, newSessionId=$diySessionId',
        );
      } catch (e) {
        logE(
          '❌ 更新 diySessionId 失败: conversationId=$conversationId, error=$e',
        );
        // 回滚修改
        _conversations[index] = _conversations[index].copyWith(
          diySessionId: oldSessionId,
        );
        rethrow;
      }
    } else {
      logI(
        '⏭️ 无需更新 diySessionId: conversationId=$conversationId, oldSessionId=$oldSessionId, newSessionId=$diySessionId (只有在原sessionId为null且新的不为null时才更新)',
      );
    }

    // 验证更新结果
    final finalSessionId = _conversations[index].diySessionId;
    if (finalSessionId != diySessionId) {
      logE(
        '🚨 Session ID 更新验证失败: expected=$diySessionId, actual=$finalSessionId',
      );
    } else {
      logI(
        '✅ Session ID 更新验证成功: conversationId=$conversationId, sessionId=$finalSessionId',
      );
    }
  }

  Future<void> clearMessages(String conversationId) async {
    if (_messages.containsKey(conversationId)) {
      _messages[conversationId]?.clear();

      final index = _conversations.indexWhere((c) => c.id == conversationId);
      if (index != -1) {
        _conversations[index] = _conversations[index].copyWith(
          lastMessage: '',
          lastMessageTime: DateTime.now(),
          unreadCount: 0,
        );
      }

      resetPaginationState(conversationId);

      await _saveConversations();
      notifyListeners();
      logI('Cleared messages for conversation $conversationId');
    }
  }

  /// 更新对话的服务器配置
  Future<void> updateConversationConfig(
    String conversationId,
    String newConfigId,
  ) async {
    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index == -1) {
      logW('❌ 未找到对话: conversationId=$conversationId');
      return;
    }

    final updatedConversation = _conversations[index].copyWith(
      configId: newConfigId,
    );

    _conversations[index] = updatedConversation;
    await _saveConversations();
    notifyListeners();

    logI('✅ 已更新对话 $conversationId 的配置为 $newConfigId');
  }

  /// 更新对话的Session模型配置
  Future<void> updateConversationSessionModelConfig(
    String conversationId,
    SessionModelConfig sessionModelConfig,
  ) async {
    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index == -1) {
      logW('❌ 未找到对话: conversationId=$conversationId');
      return;
    }

    final updatedConversation = _conversations[index].copyWith(
      sessionModelConfig: sessionModelConfig,
    );

    _conversations[index] = updatedConversation;
    await _saveConversations();
    notifyListeners();

    logI('✅ 已更新对话 $conversationId 的Session模型配置');
  }
}
