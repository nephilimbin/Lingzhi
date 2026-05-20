import 'dart:math' as math;
import 'package:ai_assistant/features/chat/providers/chat_provider.dart';
import 'package:flutter/material.dart';

class VoiceRecordButton extends StatefulWidget {
  final VoidCallback? onLongPressStart;
  final Function(LongPressEndDetails)? onLongPressEnd;
  final Function(LongPressMoveUpdateDetails)? onLongPressMoveUpdate;
  final ChatProvider chatProvider;

  const VoiceRecordButton({
    required this.chatProvider,
    super.key,
    this.onLongPressStart,
    this.onLongPressEnd,
    this.onLongPressMoveUpdate,
  });

  @override
  State<VoiceRecordButton> createState() => _VoiceRecordButtonState();
}

class _VoiceRecordButtonState extends State<VoiceRecordButton>
    with TickerProviderStateMixin {
  late AnimationController _waveController;
  late AnimationController _pulseController;
  final List<double> _waveHeights = List.filled(7, 0.0);
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _waveController.addListener(_updateWaveHeights);
  }

  @override
  void dispose() {
    _waveController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _updateWaveHeights() {
    if (!mounted) {
      return;
    }
    setState(() {
      for (int i = 0; i < _waveHeights.length; i++) {
        _waveHeights[i] = _random.nextDouble() * 16 + 4;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isRecording = widget.chatProvider.isRecording;
    final isCancelling = widget.chatProvider.isCancelling;

    // 开始或停止动画
    if (isRecording && !_waveController.isAnimating) {
      _waveController.repeat();
      _pulseController.repeat();
    } else if (!isRecording && _waveController.isAnimating) {
      _waveController.stop();
      _pulseController.stop();
    }

    return GestureDetector(
      onLongPressStart: (details) {
        widget.onLongPressStart?.call();
        widget.chatProvider.handleVoicePanStart(details);
      },
      onLongPressMoveUpdate: (details) {
        widget.onLongPressMoveUpdate?.call(details);
      },
      onLongPressEnd: (details) {
        widget.onLongPressEnd?.call(details);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 48,
        decoration: BoxDecoration(
          color: isRecording
              ? isCancelling
                  ? Colors.red.withValues(alpha: 0.1)
                  : Colors.blue.withValues(alpha: 0.1)
              : const Color(0xFFF5F7F9),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 8,
              spreadRadius: 0,
              offset: const Offset(0, 3),
            ),
            if (isRecording)
              BoxShadow(
                color: (isCancelling ? Colors.red : Colors.blue)
                    .withValues(alpha: 0.2),
                blurRadius: 15,
                spreadRadius: 2,
                offset: const Offset(0, 0),
              ),
          ],
        ),
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: isRecording
                ? _buildRecordingContent(isCancelling)
                : _buildNormalContent(),
          ),
        ),
      ),
    );
  }

  Widget _buildNormalContent() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.mic_outlined,
          color: Colors.grey.shade700,
          size: 20,
        ),
        const SizedBox(width: 8),
        const Text(
          "按住说话",
          style: TextStyle(
            color: Color.fromARGB(255, 9, 9, 9),
            fontSize: 16,
            fontWeight: FontWeight.normal,
          ),
        ),
      ],
    );
  }

  Widget _buildRecordingContent(bool isCancelling) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 麦克风图标和脉冲动画
        Stack(
          alignment: Alignment.center,
          children: [
            // 脉冲圆圈
            if (!isCancelling)
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  final progress = _pulseController.value;
                  final size = 24 + (math.sin(progress * 2 * math.pi) * 8);
                  return Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.blue.withValues(alpha: 0.3 * (1 - progress)),
                        width: 1.5,
                      ),
                    ),
                  );
                },
              ),
            // 麦克风图标
            Icon(
              Icons.mic,
              color: isCancelling ? Colors.red.shade700 : Colors.blue.shade700,
              size: 20,
            ),
          ],
        ),
        const SizedBox(width: 12),
        // 波形动画
        SizedBox(
          width: 60,
          height: 24,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: _waveHeights.map((height) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 2,
                height: isCancelling ? 8 : height,
                decoration: BoxDecoration(
                  color: isCancelling
                      ? Colors.red.shade400
                      : Colors.blue.shade400,
                  borderRadius: BorderRadius.circular(1),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(width: 12),
        // 文字提示
        Text(
          isCancelling ? "松开取消" : "松开发送",
          style: TextStyle(
            color: isCancelling ? Colors.red.shade700 : Colors.blue.shade700,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}