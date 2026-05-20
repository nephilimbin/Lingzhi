import 'package:flutter/material.dart';
import 'package:ai_assistant/core/models/chat_service_config.dart';

class DiyConfig extends ChatServiceConfig {
  final String websocketUrl;
  final String macAddress;
  final String token;

  DiyConfig({
    required super.id,
    required super.name,
    required this.websocketUrl,
    required this.macAddress,
    required this.token,
    super.icon = const ServiceIcon(
      iconData: Icons.smart_toy,
      backgroundColor: Color(0xFF9C27B0),
      iconColor: Color(0xFFFFFFFF),
    ),
  }) : super(
         capabilities: const ServiceCapabilities(
           supportsVoiceInput: true, // 支持语音
           supportsStreamingText: true,
         ),
       );

  factory DiyConfig.fromJson(Map<String, dynamic> json) {
    return DiyConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      websocketUrl: json['websocketUrl'] as String,
      macAddress: json['macAddress'] as String? ?? '',
      token: json['token'] as String? ?? '',
      icon: json.containsKey('icon') && json['icon'] != null
          ? ServiceIcon.fromJson(json['icon'] as Map<String, dynamic>)
          : ServiceIcon.defaultIcon(),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'websocketUrl': websocketUrl,
      'macAddress': macAddress,
      'token': token,
      'icon': icon.toJson(),
    };
  }

  DiyConfig copyWith({
    String? name,
    String? websocketUrl,
    String? macAddress,
    String? token,
    ServiceIcon? icon,
  }) {
    return DiyConfig(
      id: id,
      name: name ?? this.name,
      websocketUrl: websocketUrl ?? this.websocketUrl,
      macAddress: macAddress ?? this.macAddress,
      token: token ?? this.token,
      icon: icon ?? this.icon,
    );
  }
}
