import 'package:flutter/material.dart';

/// 声波动画条组件
/// 显示音频波形动画，用于 WebRTC 通话界面
class AudioWaveformBars extends StatelessWidget {
  /// 声波条数量
  final int barCount;

  /// 声波高度数组
  final List<double> barHeights;

  /// 是否正在接收音频
  final bool isReceivingAudio;

  /// 声波条宽度
  final double barWidth;

  /// 声波条之间的间距
  final double spacing;

  /// 渐变起始颜色
  final Color startColor;

  /// 渐变结束颜色
  final Color endColor;

  const AudioWaveformBars({
    required this.barHeights,
    super.key,
    this.barCount = 12,
    this.isReceivingAudio = false,
    this.barWidth = 8,
    this.spacing = 2,
    this.startColor = const Color(0xFF60A5FA),
    this.endColor = const Color(0xFFA855F7),
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: List.generate(barCount, (index) {
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: spacing),
          child: AnimatedContainer(
            duration: Duration(
              milliseconds: isReceivingAudio ? 200 : 500,
            ),
            curve: Curves.easeInOut,
            width: barWidth,
            height: barHeights[index],
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [startColor, endColor],
              ),
            ),
          ),
        );
      }),
    );
  }
}
