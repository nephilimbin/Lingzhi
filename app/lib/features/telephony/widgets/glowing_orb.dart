import 'package:flutter/material.dart';

/// 发光球体动画组件
/// 基于径向渐变实现的呼吸脉冲效果球体，用于语音通话界面
/// 匹配 Figma 设计: scale [1, 1.05, 1], opacity [0.8, 0.95, 0.8], easeInOut
class GlowingOrb extends StatelessWidget {
  /// 动画（已应用 easeInOut 曲线）
  final Animation<double> animation;

  /// 球体直径
  final double diameter;

  const GlowingOrb({
    required this.animation,
    super.key,
    this.diameter = 288,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        // 匹配 Figma: scale [1, 1.05, 1], opacity [0.8, 0.95, 0.8]
        // animation.value 已通过 easeInOut 曲线处理，范围 0.0 ~ 1.0
        // 往返动画: 0 → 1 → 0 (通过 reverse: true 实现)
        final value = animation.value;

        // scale: 1.0 + (1.05 - 1.0) * value = 1.0 + 0.05 * value
        final scale = 1.0 + 0.05 * value;

        // opacity: 0.8 + (0.95 - 0.8) * value = 0.8 + 0.15 * value
        final opacity = 0.8 + 0.15 * value;

        return Transform.scale(
          scale: scale,
          child: Opacity(
            opacity: opacity,
            child: Container(
              width: diameter,
              height: diameter,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  // 焦点在 30% 40% 位置 (对应 Figma: circle at 30% 40%)
                  center: const Alignment(-0.4, -0.2),
                  radius: 1.0,
                  stops: const [0.0, 0.3, 0.6, 1.0],
                  colors: [
                    // 中心：淡紫色 rgba(220, 180, 255, 0.8)
                    const Color(0xFFDCB4FF).withValues(alpha: 0.8),
                    // 30%：紫色 rgba(180, 150, 255, 0.6)
                    const Color(0xFFB496FF).withValues(alpha: 0.6),
                    // 60%：蓝紫色 rgba(140, 180, 255, 0.4)
                    const Color(0xFF8CB4FF).withValues(alpha: 0.4),
                    // 边缘：浅蓝色 rgba(200, 230, 255, 0.2)
                    const Color(0xFFC8E6FF).withValues(alpha: 0.2),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
