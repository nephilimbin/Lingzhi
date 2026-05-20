import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:ai_assistant/features/telephony/providers/telephony_provider.dart';
import 'package:ai_assistant/features/telephony/widgets/glowing_orb.dart';
import 'package:ai_assistant/core/services/websocket_manager.dart';

/// Telephony 语音通话页面
/// 连接到fastrtc后端服务，实现实时语音对话功能
class TelephonyScreen extends StatefulWidget {
  final DiyWebSocketManager webSocketManager;
  final String sessionId;
  final String serverUrl;

  const TelephonyScreen({
    required this.webSocketManager,
    required this.sessionId,
    required this.serverUrl,
    super.key,
  });

  @override
  State<TelephonyScreen> createState() => _TelephonyScreenState();
}

class _TelephonyScreenState extends State<TelephonyScreen>
    with TickerProviderStateMixin {
  late final TelephonyProvider _provider;

  // --- 动画控制器 ---
  late AnimationController _bgController;
  late AnimationController _breathingController;
  late Animation<double> _breathingAnimation;

  @override
  void initState() {
    super.initState();
    _provider = TelephonyProvider(
      serverUrl: widget.serverUrl,
      webSocketManager: widget.webSocketManager,
      sessionId: widget.sessionId,
      context: context,
    );

    // 1. 背景流动动画 (16 秒循环)
    _bgController = AnimationController(
      duration: const Duration(seconds: 16),
      vsync: this,
    )..repeat();

    // 2. 中央呼吸光晕动画 (4 秒周期，easeInOut 曲线)
    // 匹配 Figma: scale [1, 1.05, 1], opacity [0.8, 0.95, 0.8]
    _breathingController = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    );
    // 使用 easeInOut 曲线的往返动画
    _breathingAnimation = CurvedAnimation(
      parent: _breathingController,
      curve: Curves.easeInOut,
    );
    _breathingController.repeat(reverse: true);

    // 异步初始化
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // 延迟初始化，避免权限检查导致的问题
      await Future.delayed(const Duration(milliseconds: 200));
      if (mounted) {
        await _provider.initialize();
        // 初始化完成后自动建立连接
        await _provider.connectToServer();
      }
    });
  }

  @override
  void dispose() {
    _bgController.dispose();
    _breathingController.dispose();
    _provider.dispose();
    super.dispose();
  }

  /// 显示权限引导弹窗
  void _showPermissionGuideDialog() {
    final theme = Theme.of(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            backgroundColor: theme.colorScheme.surface,
            title: Row(
              children: [
                const Icon(Icons.mic_off, color: Colors.orange),
                const SizedBox(width: 12),
                Text(
                  '需要麦克风权限',
                  style: TextStyle(color: theme.colorScheme.onSurface),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '语音通话功能需要使用麦克风权限。',
                  style: TextStyle(color: theme.colorScheme.onSurface),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 16,
                            color: Colors.orange[700],
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '设置路径',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.orange[700],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        Platform.isIOS
                            ? '设置 → 隐私与安全 → 麦克风 → 允许此应用访问'
                            : '设置 → 应用 → 此应用 → 权限 → 麦克风 → 允许',
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  '稍后',
                  style: TextStyle(color: theme.colorScheme.primary),
                ),
              ),
              FilledButton(
                onPressed: () {
                  // 先关闭弹窗
                  Navigator.of(context).pop();
                  // 先返回上一页
                  Navigator.of(context).pop();
                  // 然后跳转到系统设置
                  Future.microtask(() => openAppSettings());
                },
                child: const Text('去设置'),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _provider,
      child: Scaffold(
        body: Stack(
          children: [
            // -----------------------------------------------------------
            // 1. 背景层 - 多层动态渐变叠加
            // -----------------------------------------------------------
            AnimatedBuilder(
              animation: _bgController,
              builder: (context, child) {
                // 16 秒循环，每层透明度按 [1,0,0,0,1], [0,1,0,0,0] 等模式变化
                // 将 16 秒分成 5 个阶段，每个阶段约 3.2 秒
                final progress = _bgController.value;
                return Stack(
                  children: [
                    // 层1: #ffc0cb → #e6d5ff → #b3e5fc
                    _buildGradientLayer(
                      colors: const [
                        Color(0xFFFFC0CB),
                        Color(0xFFE6D5FF),
                        Color(0xFFB3E5FC),
                      ],
                      opacity: _calculateLayerOpacity(progress, 0),
                    ),
                    // 层2: #ffd5e0 → #d8c5ff → #a8d8f0
                    _buildGradientLayer(
                      colors: const [
                        Color(0xFFFFD5E0),
                        Color(0xFFD8C5FF),
                        Color(0xFFA8D8F0),
                      ],
                      opacity: _calculateLayerOpacity(progress, 1),
                    ),
                    // 层3: #ffe8f0 → #cdb8ff → #9dcfeb
                    _buildGradientLayer(
                      colors: const [
                        Color(0xFFFFE8F0),
                        Color(0xFFCDB8FF),
                        Color(0xFF9DCFEB),
                      ],
                      opacity: _calculateLayerOpacity(progress, 2),
                    ),
                    // 层4: #ffd8e5 → #d5c0ff → #a5d5f5
                    _buildGradientLayer(
                      colors: const [
                        Color(0xFFFFD8E5),
                        Color(0xFFD5C0FF),
                        Color(0xFFA5D5F5),
                      ],
                      opacity: _calculateLayerOpacity(progress, 3),
                    ),
                    // 层5: #ffccd8 → #dcc8ff → #afddf8
                    _buildGradientLayer(
                      colors: const [
                        Color(0xFFFFCCD8),
                        Color(0xFFDCC8FF),
                        Color(0xFFAFDDF8),
                      ],
                      opacity: _calculateLayerOpacity(progress, 4),
                    ),
                  ],
                );
              },
            ),

            // 本地视频渲染器（视频启用时全屏显示）
            Consumer<TelephonyProvider>(
              builder: (context, provider, _) {
                if (provider.isVideoEnabled &&
                    provider.localRenderer.videoWidth > 0) {
                  // 简化的视频显示布局 - 华为设备修复
                  // 使用 objectFit 属性直接控制视频内容的适配方式
                  // RTCVideoViewObjectFitCover 保持视频宽高比并填充整个容器
                  return SizedBox.expand(
                    child: RTCVideoView(
                      provider.localRenderer,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      mirror: false, // 后置摄像头不需要镜像
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),

            // 动态叠加层 - 视频未启用时显示（在视频层上方）
            Consumer<TelephonyProvider>(
              builder: (context, provider, _) {
                if (provider.isVideoEnabled) {
                  return const SizedBox.shrink();
                }
                // 返回一个透明的占位，背景动画已经在底层实现
                return const SizedBox.expand();
              },
            ),

            // 镜头反转按钮（仅视频启用时显示在右上角）
            Consumer<TelephonyProvider>(
              builder: (context, provider, _) {
                if (!provider.isVideoEnabled) {
                  return const SizedBox.shrink();
                }
                return Positioned(
                  top: 60, // 距离顶部安全距离
                  right: 20, // 距离右侧边距
                  child: GestureDetector(
                    onTap: () => provider.switchCamera(),
                    child: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5), // 半透明黑色
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.flip_camera_ios, // iOS 风格相机翻转图标
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                );
              },
            ),

            // -----------------------------------------------------------
            // 2. 主体内容层
            // -----------------------------------------------------------
            SafeArea(
              child: Column(
                children: [
                  // TODO: 暂时未开发该功能，后续开发， 保留该接口。
                  // --- 顶部工具栏 ---
                  // Padding(
                  //   padding: const EdgeInsets.only(
                  //     top: 24.0,
                  //     left: 16,
                  //     right: 16,
                  //   ),
                  //   child: Row(
                  //     mainAxisAlignment: MainAxisAlignment.center,
                  //     children: [
                  //       ClipRRect(
                  //         borderRadius: BorderRadius.circular(999),
                  //         child: BackdropFilter(
                  //           filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                  //           child: Container(
                  //             padding: const EdgeInsets.symmetric(
                  //               horizontal: 16,
                  //               vertical: 8,
                  //             ),
                  //             color: Colors.white.withValues(alpha: 0.9),
                  //             child: Row(
                  //               mainAxisSize: MainAxisSize.min,
                  //               children: [
                  //                 SizedBox(
                  //                   width: 16,
                  //                   height: 16,
                  //                   child: GridView.count(
                  //                     crossAxisCount: 2,
                  //                     mainAxisSpacing: 2,
                  //                     crossAxisSpacing: 2,
                  //                     padding: EdgeInsets.zero,
                  //                     children: List.generate(
                  //                       4,
                  //                       (i) => Container(
                  //                         decoration: BoxDecoration(
                  //                           color: const Color(0xFF374151),
                  //                           borderRadius: BorderRadius.circular(
                  //                             1.5,
                  //                           ),
                  //                         ),
                  //                       ),
                  //                     ),
                  //                   ),
                  //                 ),
                  //                 const SizedBox(width: 8),
                  //                 const Text(
                  //                   "选择情景",
                  //                   style: TextStyle(
                  //                     color: Color(0xFF374151),
                  //                     fontSize: 14,
                  //                     fontWeight: FontWeight.w500,
                  //                   ),
                  //                 ),
                  //               ],
                  //             ),
                  //           ),
                  //         ),
                  //       ),
                  //     ],
                  //   ),
                  // ),
                  const Spacer(),

                  // --- 中央视觉区域 ---
                  Consumer<TelephonyProvider>(
                    builder: (context, provider, _) {
                      // 视频启用时隐藏球体动画
                      if (provider.isVideoEnabled) {
                        return const SizedBox.shrink();
                      }

                      return GlowingOrb(animation: _breathingAnimation);
                    },
                  ),

                  const Spacer(),

                  // --- 底部状态指示器 ---
                  Consumer<TelephonyProvider>(
                    builder: (context, provider, _) {
                      String hintText;
                      if (provider.isMuted) {
                        hintText = "你已静音";
                      } else if (provider.isConnecting) {
                        hintText = "正在连接...";
                      } else if (provider.isConnected) {
                        hintText = "正在聆听";
                      } else {
                        hintText = "WebRTC服务未连接";
                      }

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: Column(
                          children: [
                            // 3 个跳动的点（仅连接时显示）
                            if (provider.isConnected && !provider.isMuted)
                              _buildPulsingDots(),
                            const SizedBox(height: 12),
                            Text(
                              hintText,
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.6),
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                  // --- 底部按钮区域 ---
                  Consumer<TelephonyProvider>(
                    builder: (context, provider, _) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32.0,
                          vertical: 20,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // 1. 静音按钮
                            _buildCircleButton(
                              icon:
                                  provider.isMuted
                                      ? Icons.mic_off
                                      : Icons.mic_none,
                              isActive: provider.isMuted,
                              activeColor: const Color(0xFFEF4444),
                              onTap: () => provider.toggleMute(),
                            ),

                            // 2. 连接/断开按钮
                            _buildCircleButton(
                              icon:
                                  provider.isConnected
                                      ? Icons.link_off
                                      : Icons.link,
                              isActive: provider.isConnected,
                              activeColor: const Color(0xFF3B82F6),
                              onTap: () async {
                                if (provider.isConnected) {
                                  provider.disconnect();
                                } else {
                                  // 连接前检查权限（添加异常保护）
                                  try {
                                    final hasPermission =
                                        await _provider
                                            .checkMicrophonePermission();
                                    if (!hasPermission) {
                                      _showPermissionGuideDialog();
                                      return;
                                    }
                                    provider.connectToServer();
                                  } catch (e) {
                                    // 权限检查失败，直接尝试连接
                                    provider.connectToServer();
                                  }
                                }
                              },
                            ),

                            // 3. 摄像头按钮
                            _buildCircleButton(
                              icon:
                                  provider.isVideoEnabled
                                      ? Icons.videocam
                                      : Icons.videocam_off,
                              isActive: provider.isVideoEnabled,
                              activeColor: const Color(0xFF22C55E),
                              onTap: () async {
                                await provider.toggleVideo();
                              },
                            ),

                            // 4. 退出按钮
                            _buildCircleButton(
                              icon: Icons.close,
                              isActive: false,
                              activeColor: Colors.transparent,
                              isExit: true,
                              onTap: () => Navigator.of(context).pop(),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建渐变层
  Widget _buildGradientLayer({
    required List<Color> colors,
    required double opacity,
  }) {
    return Positioned.fill(
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
            ),
          ),
        ),
      ),
    );
  }

  /// 计算每层透明度
  /// 16 秒循环，匹配 Figma 关键帧透明度数组 + easeInOut 插值
  /// 每层透明度关键帧：
  /// - 层0: [1, 0, 0, 0, 1]
  /// - 层1: [0, 1, 0, 0, 0]
  /// - 层2: [0, 0, 1, 0, 0]
  /// - 层3: [0, 0, 0, 1, 0]
  /// - 层4: [0, 0, 0, 0, 1]
  double _calculateLayerOpacity(double progress, int layerIndex) {
    const int totalLayers = 5;
    const double segmentWidth = 1.0 / totalLayers;

    // 每层的透明度关键帧
    final keyframes = List.generate(totalLayers + 1, (i) {
      final idx = (layerIndex + i) % totalLayers;
      return idx == 0 ? 1.0 : 0.0;
    });

    // 找到当前进度所在的区间
    final segmentIndex = (progress / segmentWidth).floor();
    final localProgress =
        (progress - segmentIndex * segmentWidth) / segmentWidth;

    // 使用 easeInOut 曲线插值
    final easedProgress = _easeInOut(localProgress);

    // 在两个关键帧之间插值
    final fromOpacity = keyframes[segmentIndex];
    final toOpacity = keyframes[segmentIndex + 1];

    return fromOpacity + (toOpacity - fromOpacity) * easedProgress;
  }

  /// easeInOut 缓动函数
  /// 匹配 Figma motion 的 easeInOut 效果
  double _easeInOut(double t) {
    return t < 0.5 ? 2 * t * t : 1 - math.pow(-2 * t + 2, 2) / 2;
  }

  /// 构建 3 个跳动的点
  Widget _buildPulsingDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (index) {
        return AnimatedBuilder(
          animation: _breathingController,
          builder: (context, child) {
            // 每个点有不同的延迟
            final delay = index * 0.15;
            final adjustedValue = (_breathingController.value + delay) % 1.0;
            // 透明度在 0.3 到 1.0 之间变化
            final opacity =
                0.3 + 0.7 * (math.sin(adjustedValue * math.pi).abs());

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.grey.withValues(alpha: opacity),
              ),
            );
          },
        );
      }),
    );
  }

  /// 封装组件：底部圆形按钮
  Widget _buildCircleButton({
    required IconData icon,
    required bool isActive,
    required Color activeColor,
    required VoidCallback onTap,
    bool isExit = false,
    bool enableHapticFeedback = true,
  }) {
    Color bgColor;
    Color iconColor;
    List<BoxShadow>? boxShadow;

    if (isExit) {
      // 参考样式：#DCE0EA 50% 透明度
      bgColor = const Color(0x7FDCE0EA);
      iconColor = const Color(0xFF374151);
      // 无阴影
      boxShadow = const [];
    } else if (isActive) {
      bgColor = activeColor.withValues(alpha: 0.9);
      iconColor = Colors.white;
      // 无阴影
      boxShadow = const [];
    } else {
      // 普通状态：#DCE0EA 50% 透明度
      bgColor = const Color(0x7FDCE0EA);
      iconColor = const Color(0xFF374151);
      // 无阴影
      boxShadow = const [];
    }

    return GestureDetector(
      onTap: () {
        if (enableHapticFeedback) {
          HapticFeedback.lightImpact();
        }
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 74,
        height: 74,
        decoration: BoxDecoration(
          color: bgColor,
          shape: BoxShape.circle,
          boxShadow: boxShadow,
        ),
        child: Center(child: Icon(icon, color: iconColor, size: 28)),
      ),
    );
  }
}
