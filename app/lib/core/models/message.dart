enum MessageRole { user, assistant, system }

class Message {
  final String id;
  final String conversationId;
  final MessageRole role;
  final String content;
  final DateTime timestamp;
  final bool isRead;
  final bool isImage;
  final String? imageLocalPath;
  final String? fileId;
  final String? sessionResponseId;
  final bool isTyping;

  Message({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.content,
    required this.timestamp,
    this.isRead = false,
    this.isImage = false,
    this.imageLocalPath,
    this.fileId,
    this.sessionResponseId,
    this.isTyping = false,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'],
      conversationId: json['conversationId'],
      role: MessageRole.values.byName(json['role']),
      content: json['content'],
      timestamp: DateTime.parse(json['timestamp']),
      isRead: json['isRead'] ?? false,
      isImage: json['isImage'] ?? false,
      imageLocalPath: json['imageLocalPath'],
      fileId: json['fileId'],
      sessionResponseId: json['sessionResponseId'],
      isTyping: json['isTyping'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'conversationId': conversationId,
      'role': role.name,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'isRead': isRead,
      'isImage': isImage,
      'imageLocalPath': imageLocalPath,
      'fileId': fileId,
      'sessionResponseId': sessionResponseId,
      'isTyping': isTyping,
    };
  }

  Message copyWith({
    String? id,
    String? conversationId,
    MessageRole? role,
    String? content,
    DateTime? timestamp,
    bool? isRead,
    bool? isImage,
    String? imageLocalPath,
    String? fileId,
    String? sessionResponseId,
    bool? isTyping,
  }) {
    return Message(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      role: role ?? this.role,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      isRead: isRead ?? this.isRead,
      isImage: isImage ?? this.isImage,
      imageLocalPath: imageLocalPath ?? this.imageLocalPath,
      fileId: fileId ?? this.fileId,
      sessionResponseId: sessionResponseId ?? this.sessionResponseId,
      isTyping: isTyping ?? this.isTyping,
    );
  }
}
