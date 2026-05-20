import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ai_assistant/core/models/conversation.dart';
import 'package:ai_assistant/core/providers/config_provider.dart';

class ConversationTile extends StatelessWidget {
  final Conversation conversation;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool isFirstItem;

  const ConversationTile({
    required this.conversation,
    super.key,
    this.onTap,
    this.onLongPress,
    this.isFirstItem = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      margin: EdgeInsets.zero,
      decoration: BoxDecoration(
        color: isFirstItem
            ? (isDark ? const Color(0xFF1E1E1E) : Colors.grey.shade100)
            : theme.colorScheme.surface,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                _buildAvatar(context),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    conversation.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: theme.colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                _buildTypeTag(context),
                              ],
                            ),
                          ),
                          Text(
                            _formatTime(conversation.lastMessageTime),
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark ? const Color(0xFF757575) : Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        conversation.lastMessage,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? const Color(0xFFB0B0B0) : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  child: Icon(
                    Icons.chevron_right,
                    color: isDark ? const Color(0xFF4A4A4A) : Colors.grey.shade300,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTypeTag(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bool isDify = conversation.type == ConversationType.dify;
    String label = isDify ? '文本' : '语音';
    bool configFound = false;

    // 如果有配置ID且不为空，则显示配置名称
    if (conversation.configId.isNotEmpty) {
      final configProvider = Provider.of<ConfigProvider>(
        context,
        listen: false,
      );

      if (isDify) {
        // 尝试查找匹配的Dify配置
        final matchingConfig =
            configProvider.difyConfigs
                .where((config) => config.id == conversation.configId)
                .firstOrNull;
        if (matchingConfig != null) {
          label = matchingConfig.name;
          configFound = true;
        }
      } else {
        // 尝试查找匹配的自定义配置
        final matchingConfig =
            configProvider.diyConfigs
                .where((config) => config.id == conversation.configId)
                .firstOrNull;
        if (matchingConfig != null) {
          label = matchingConfig.name;
          configFound = true;
        }
      }
    }

    // 配置缺失时显示警告样式
    if (conversation.configId.isNotEmpty && !configFound) {
      label = '无服务';
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF424242) : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isDify
            ? (isDark ? const Color(0xFF1E3A8A) : Colors.blue.shade50)
            : (isDark ? const Color(0xFF4A148C) : Colors.purple.shade50),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: isDify ? Colors.blue.shade400 : Colors.purple.shade400,
        ),
      ),
    );
  }

  Widget _buildAvatar(BuildContext context) {
    /// 优先使用服务配置的图标，如果未找到则使用默认图标
    final configProvider = Provider.of<ConfigProvider>(
      context,
      listen: false,
    );

    /// 查找匹配的配置
    if (conversation.configId.isNotEmpty) {
      if (conversation.type == ConversationType.dify) {
        /// 尝试查找匹配的Dify配置
        final matchingConfig =
            configProvider.difyConfigs
                .where((config) => config.id == conversation.configId)
                .firstOrNull;
        if (matchingConfig != null) {
          /// 使用配置的自定义图标
          return CircleAvatar(
            radius: 24,
            backgroundColor: matchingConfig.icon.backgroundColor,
            child: Icon(
              matchingConfig.icon.iconData,
              color: matchingConfig.icon.iconColor,
              size: 24,
            ),
          );
        }
      } else {
        /// 尝试查找匹配的自定义配置
        final matchingConfig =
            configProvider.diyConfigs
                .where((config) => config.id == conversation.configId)
                .firstOrNull;
        if (matchingConfig != null) {
          /// 使用配置的自定义图标
          return CircleAvatar(
            radius: 24,
            backgroundColor: matchingConfig.icon.backgroundColor,
            child: Icon(
              matchingConfig.icon.iconData,
              color: matchingConfig.icon.iconColor,
              size: 24,
            ),
          );
        }
      }
    }

    /// 未找到配置时显示错误图标
    return CircleAvatar(
      radius: 24,
      backgroundColor: Colors.red.shade400,
      child: const Icon(
        Icons.error_outline,
        color: Colors.white,
        size: 24,
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0 && difference.inDays <= 1) {
      return '昨天';
    } else if (difference.inDays > 1 && difference.inDays <= 7) {
      return '周${_getWeekday(dateTime.weekday)}';
    } else {
      // 当天显示时间
      final hour = dateTime.hour.toString().padLeft(2, '0');
      final minute = dateTime.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    }
  }

  String _getWeekday(int weekday) {
    switch (weekday) {
      case 1:
        return '一';
      case 2:
        return '二';
      case 3:
        return '三';
      case 4:
        return '四';
      case 5:
        return '五';
      case 6:
        return '六';
      case 7:
        return '日';
      default:
        return '';
    }
  }
}
