import 'package:flutter/material.dart';
import 'package:ai_assistant/core/models/chat_service_config.dart';

class DifyConfig extends ChatServiceConfig {
  final String apiUrl;
  final String apiKey;

  DifyConfig({
    required super.id,
    required super.name,
    required this.apiUrl,
    required this.apiKey,
    super.icon = const ServiceIcon(
      iconData: Icons.chat_bubble_outline,
      backgroundColor: Color(0xFF2196F3),
      iconColor: Color(0xFFFFFFFF),
    ),
  }) : super(
         capabilities: const ServiceCapabilities(
           supportsVoiceInput: false, // Dify 不支持语音
           supportsStreamingText: true,
         ),
       );

  factory DifyConfig.fromJson(Map<String, dynamic> json) {
    return DifyConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      apiUrl: json['apiUrl'] as String,
      apiKey: json['apiKey'] as String,
      icon: json.containsKey('icon') && json['icon'] != null
          ? ServiceIcon.fromJson(json['icon'] as Map<String, dynamic>)
          : const ServiceIcon(
              iconData: Icons.chat_bubble_outline,
              backgroundColor: Color(0xFF2196F3),
              iconColor: Color(0xFFFFFFFF),
            ),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'apiUrl': apiUrl,
      'apiKey': apiKey,
      'icon': icon.toJson(),
    };
  }

  DifyConfig copyWith({
    String? id,
    String? name,
    String? apiUrl,
    String? apiKey,
    ServiceIcon? icon,
  }) {
    return DifyConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      apiUrl: apiUrl ?? this.apiUrl,
      apiKey: apiKey ?? this.apiKey,
      icon: icon ?? this.icon,
    );
  }
}
