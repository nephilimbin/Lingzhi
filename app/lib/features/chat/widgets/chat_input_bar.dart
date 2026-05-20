import 'package:ai_assistant/core/models/conversation.dart';
import 'package:ai_assistant/features/chat/providers/chat_provider.dart';
import 'package:ai_assistant/features/chat/widgets/voice_record_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

class ChatInputBar extends StatelessWidget {
  const ChatInputBar({super.key});

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            spreadRadius: 0,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.only(left: 16, top: 12, right: 16, bottom: 8 + bottomPadding),
      child:
          chatProvider.isVoiceInputMode
              ? _buildVoiceInput(context, chatProvider)
              : _buildTextInput(context, chatProvider),
    );
  }

  Widget _buildTextInput(BuildContext context, ChatProvider chatProvider) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF5F7F9);
    final iconColor = isDark ? const Color(0xFFB0B0B0) : Colors.grey.shade700;
    final textColor = isDark ? const Color(0xFFE0E0E0) : const Color(0xFF1F2937);
    final hintColor = isDark ? const Color(0xFF757575) : const Color(0xFF9CA3AF);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 语音输入按钮
        if (chatProvider.conversation.type == ConversationType.diy)
          InkWell(
            onTap: () => chatProvider.toggleInputMode(),
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(23),
              ),
              child: Icon(
                Icons.mic_outlined,
                color: iconColor,
                size: 24,
              ),
            ),
          ),
        if (chatProvider.conversation.type == ConversationType.diy)
          const SizedBox(width: 8),
        // 文本输入框
        Expanded(
          child: GestureDetector(
            onLongPress:
                chatProvider.conversation.type == ConversationType.diy &&
                        !chatProvider.isVoiceInputMode
                    ? () {
                      // 长按切换到语音模式时隐藏键盘
                      FocusScope.of(context).unfocus();
                      chatProvider.toggleInputMode();
                      HapticFeedback.mediumImpact();
                    }
                    : null,
            child: Container(
              height: 46,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(23),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.07),
                    blurRadius: 8,
                    spreadRadius: 0,
                    offset: const Offset(0, 3),
                  ),
                  BoxShadow(
                    color: isDark ? const Color(0xFF1E1E1E).withValues(alpha: 0.8) : Colors.white.withValues(alpha: 0.8),
                    blurRadius: 5,
                    spreadRadius: 0,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: chatProvider.textController,
                      focusNode: chatProvider.textFocusNode,
                      decoration: InputDecoration(
                        hintText: '发消息...',
                        hintStyle: TextStyle(
                          color: hintColor,
                          fontSize: 16,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                      ),
                      style: TextStyle(
                        color: textColor,
                        fontSize: 16,
                      ),
                      maxLines: 1,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (text) {
                        if (text.trim().isNotEmpty) {
                          chatProvider.sendMessage();
                        }
                      },
                      keyboardType: TextInputType.text,
                      textCapitalization: TextCapitalization.sentences,
                      enableSuggestions: true,
                      autocorrect: true,
                      cursorColor: Colors.blueAccent,
                      cursorWidth: 2.0,
                      cursorHeight: 20.0,
                      autofocus: false,
                      enableInteractiveSelection: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // 加号按钮（共用组件）
        _buildAddButton(context, chatProvider, bgColor, hintColor),
      ],
    );
  }

  Widget _buildVoiceInput(BuildContext context, ChatProvider chatProvider) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF5F7F9);
    final iconColor = isDark ? const Color(0xFFB0B0B0) : Colors.grey.shade700;
    final hintColor = isDark ? const Color(0xFF757575) : const Color(0xFF9CA3AF);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 键盘按钮 (切换回文本模式)
        InkWell(
          onTap: () => chatProvider.toggleInputMode(),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(23),
            ),
            child: Icon(
              Icons.keyboard_alt_outlined,
              color: iconColor,
              size: 24,
            ),
          ),
        ),
        const SizedBox(width: 8),
        // 按住说话按钮
        Expanded(
          child: VoiceRecordButton(
            chatProvider: chatProvider,
            onLongPressStart: () {
              chatProvider.startRecording();
            },
            onLongPressMoveUpdate: (details) {
              chatProvider.handleVoicePanUpdate(details);
            },
            onLongPressEnd: (details) {
              chatProvider.handleVoicePanEnd(details);
            },
          ),
        ),
        const SizedBox(width: 8),
        // 加号按钮（共用组件）
        _buildAddButton(context, chatProvider, bgColor, hintColor),
      ],
    );
  }

  /// 加号按钮（共用组件，所有会话类型统一显示）
  Widget _buildAddButton(
    BuildContext context,
    ChatProvider chatProvider,
    Color bgColor,
    Color iconColor,
  ) {
    return InkWell(
      onTap: () => _onAddButtonPressed(context, chatProvider),
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(23),
        ),
        child: Icon(
          Icons.add_circle_outline,
          color: iconColor,
          size: 24,
        ),
      ),
    );
  }

  /// 加号按钮点击处理（预留扩展接口）
  /// 后期可根据会话类型扩展不同功能
  void _onAddButtonPressed(BuildContext context, ChatProvider chatProvider) {
    // 目前仅 dify 类型支持图片选择功能
    if (chatProvider.conversation.type == ConversationType.dify) {
      _showImagePicker(context, chatProvider);
    }
    // 其他类型暂时不做处理，预留扩展点
  }

  void _showImagePicker(BuildContext context, ChatProvider chatProvider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder:
          (context) => Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    '选择图片',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.camera_alt, color: Theme.of(context).colorScheme.onSurface),
                  title: Text('拍照', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                  onTap: () {
                    Navigator.pop(context);
                    chatProvider.pickImage(ImageSource.camera);
                  },
                ),
                ListTile(
                  leading: Icon(Icons.photo_library, color: Theme.of(context).colorScheme.onSurface),
                  title: Text('从相册选择', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                  onTap: () {
                    Navigator.pop(context);
                    chatProvider.pickImage(ImageSource.gallery);
                  },
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
    );
  }
}
