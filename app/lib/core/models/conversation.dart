import 'package:ai_assistant/core/utils/app_logger.dart';
import 'package:ai_assistant/core/models/session_model_config.dart';

enum ConversationType { dify, diy }

class Conversation {
  final String id;
  final String title;
  final ConversationType type;
  final String
  configId; // For both Diy and Dify conversations, references the config
  final DateTime lastMessageTime;
  final String lastMessage;
  final int unreadCount;
  final bool isPinned;
  final String? diySessionId;

  /// Session层级的模型配置
  /// 这个配置独立于服务器的全局模型配置
  final SessionModelConfig? sessionModelConfig;

  Conversation({
    required this.id,
    required this.title,
    required this.type,
    required this.lastMessageTime,
    required this.lastMessage,
    this.configId = '',
    this.unreadCount = 0,
    this.isPinned = false,
    this.diySessionId,
    this.sessionModelConfig,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) {
    // 🔍 调试：检查JSON中的diySessionId
    final sessionId = json['diySessionId'];

    // 解析sessionModelConfig
    SessionModelConfig? sessionConfig;
    final sessionConfigJson = json['sessionModelConfig'];
    if (sessionConfigJson != null && sessionConfigJson is Map<String, dynamic>) {
      try {
        sessionConfig = SessionModelConfig.fromJson(sessionConfigJson);
      } catch (e) {
        logW('解析sessionModelConfig失败: $e');
      }
    }

    return Conversation(
      id: json['id'],
      title: json['title'],
      type: ConversationType.values.byName(json['type']),
      configId: json['configId'] ?? '',
      lastMessageTime: DateTime.parse(json['lastMessageTime']),
      lastMessage: json['lastMessage'],
      unreadCount: json['unreadCount'] ?? 0,
      isPinned: json['isPinned'] ?? false,
      diySessionId: sessionId,
      sessionModelConfig: sessionConfig,
    );
  }

  Map<String, dynamic> toJson() {
    // 🔍 调试：检查即将序列化的diySessionId

    final jsonMap = {
      'id': id,
      'title': title,
      'type': type.name,
      'configId': configId,
      'lastMessageTime': lastMessageTime.toIso8601String(),
      'lastMessage': lastMessage,
      'unreadCount': unreadCount,
      'isPinned': isPinned,
      'diySessionId': diySessionId,
      'sessionModelConfig': sessionModelConfig?.toJson(),
    };

    return jsonMap;
  }

  Conversation copyWith({
    String? title,
    ConversationType? type,
    String? configId,
    DateTime? lastMessageTime,
    String? lastMessage,
    int? unreadCount,
    bool? isPinned,
    String? diySessionId,
    SessionModelConfig? sessionModelConfig,
  }) {
    return Conversation(
      id: id,
      title: title ?? this.title,
      type: type ?? this.type,
      configId: configId ?? this.configId,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      lastMessage: lastMessage ?? this.lastMessage,
      unreadCount: unreadCount ?? this.unreadCount,
      isPinned: isPinned ?? this.isPinned,
      diySessionId: diySessionId ?? this.diySessionId,
      sessionModelConfig: sessionModelConfig ?? this.sessionModelConfig,
    );
  }
}
