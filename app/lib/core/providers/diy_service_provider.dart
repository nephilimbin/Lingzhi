import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:ai_assistant/core/models/diy_config.dart';
import 'package:ai_assistant/core/models/conversation.dart';
import 'package:ai_assistant/core/api/diy_api.dart';
import 'package:ai_assistant/core/providers/config_provider.dart';
import 'package:ai_assistant/core/providers/conversation_provider.dart';
import 'package:ai_assistant/core/utils/app_logger.dart';

class DiyServiceProvider extends ChangeNotifier {
  final ConfigProvider _configProvider;
  final ConversationProvider _conversationProvider;
  final Map<String, DiyService> _serviceCache = {};

  DiyServiceProvider(this._configProvider, this._conversationProvider);

  Future<DiyService> getServiceForConversation(
    Conversation conversation,
  ) async {
    final conversationId = conversation.id;

    // 每次都从ConfigProvider读取最新配置
    final configId = conversation.configId;
    if (configId.isEmpty) {
      throw Exception('Conversation ${conversation.id} has no configId.');
    }

    final diyConfig = _configProvider.diyConfigs
        .whereType<DiyConfig>()
        .firstWhere(
          (config) => config.id == configId,
          orElse:
              () => throw Exception("DiyConfig ID '$configId' not found."),
        );

    // 如果缓存存在且配置相同，复用服务实例
    DiyService? cachedService = _serviceCache[conversationId];
    if (cachedService != null) {
      // 检查配置是否变化
      final configChanged = cachedService.websocketUrl != diyConfig.websocketUrl ||
                           cachedService.macAddress != diyConfig.macAddress ||
                           cachedService.token != diyConfig.token;

      if (!configChanged && cachedService.isConnected) {
        logI('复用缓存的DiyService: conversationId=$conversationId');
        // 同步Session ID
        final latestSessionId = conversation.diySessionId;
        if (latestSessionId != null && latestSessionId.isNotEmpty) {
          if (cachedService.sessionId != latestSessionId) {
            cachedService.validateAndRestoreSessionId(latestSessionId);
          }
        }
        return cachedService;
      }

      // 配置变化或未连接，重新创建服务
      logI('配置变化，重新创建服务: conversationId=$conversationId');
      disposeService(conversationId);
    }

    final currentSessionId = conversation.diySessionId;
    logI(
      '创建DiyService: conversationId=${conversation.id}, sessionId=$currentSessionId',
    );

    final service = DiyService(
      websocketUrl: diyConfig.websocketUrl,
      macAddress: diyConfig.macAddress,
      token: diyConfig.token,
      sessionId: currentSessionId,
      onSessionIdUpdate: (newSessionId) async {
        logI(
          '🔄 收到Session ID更新回调: conversationId=${conversation.id}, newSessionId=$newSessionId',
        );

        if (newSessionId != null && newSessionId.isNotEmpty) {
          try {
            await _conversationProvider.updateDiySessionId(
              conversation.id,
              newSessionId,
            );

            // 🔍 验证更新后的状态
            final afterConversation = _conversationProvider.getConversationById(
              conversation.id,
            );
            final afterSessionId = afterConversation?.diySessionId;

            if (afterSessionId == newSessionId) {
              logI(
                '🎉 Session ID更新成功: conversationId=${conversation.id}, sessionId=$newSessionId',
              );
            } else {
              logE(
                '❌ Session ID更新失败: conversationId=${conversation.id}, expected=$newSessionId, actual=$afterSessionId',
              );
            }
          } catch (e) {
            logE(
              '❌ Session ID更新失败: conversationId=${conversation.id}, sessionId=$newSessionId, error=$e',
            );
          }
        } else {
          logW(
            '⚠️ 收到无效的Session ID: conversationId=${conversation.id}, newSessionId=$newSessionId',
          );
        }
      },
    );

    _serviceCache[conversationId] = service;
    await service.connectWebSocket();

    return service;
  }

  void disposeService(String conversationId) {
    final service = _serviceCache.remove(conversationId);
    if (service != null) {
      logI('Disposing service for conversation $conversationId');
      service.dispose();  // 这会停止WebSocket连接和重连机制
      logI('Disposed and removed service for conversation $conversationId');
    }
  }

  @override
  void dispose() {
    logI('Disposing all cached services...');
    for (var service in _serviceCache.values) {
      service.dispose();
    }
    _serviceCache.clear();
    super.dispose();
  }
}
