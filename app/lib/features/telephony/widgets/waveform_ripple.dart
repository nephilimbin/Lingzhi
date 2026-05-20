import 'package:flutter/material.dart';

/// 声波扩散圆环动画组件
/// 从中心向外扩散的多层圆环效果，用于 WebRTC 连接状态指示
class WaveformRipple extends StatelessWidget {
  /// 动画控制器
  final AnimationController controller;

  /// 圆环层数
  final int ringCount;

  /// 初始圆环大小
  final double initialSize;

  /// 圆环边框宽度
  final double borderWidth;

  /// 圆环颜色
  final Color color;

  const WaveformRipple({
    required this.controller,
    super.key,
    this.ringCount = 3,
    this.initialSize = 100,
    this.borderWidth = 2,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: List.generate(ringCount, (ringIndex) {
        return AnimatedBuilder(
          animation: controller,
          builder: (context, child) {
            // 每层圆环有延迟，形成扩散效果
            double delay = ringIndex / ringCount;
            double animValue = (controller.value + delay) % 1.0;
            double scale = 0.5 + animValue * 1.0;
            double opacity = 1.0 - animValue;

            return Transform.scale(
              scale: scale,
              child: Container(
                width: initialSize,
                height: initialSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: color.withValues(alpha: opacity * 0.5),
                    width: borderWidth,
                  ),
                ),
              ),
            );
          },
        );
      }),
    );
  }
}
