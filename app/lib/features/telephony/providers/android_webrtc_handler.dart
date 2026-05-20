import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:ai_assistant/core/utils/app_logger.dart';

/// Android WebRTC 处理器
///
/// 职责：
/// - 管理 Android 平台的 WebRTC 视频逻辑
/// - 使用 active: true（立即激活，不同于 iOS 的对称触发）
/// - 支持 degradationPreference 配置（MAINTAIN_RESOLUTION）
/// - 移除 scalabilityMode 避免华为设备兼容性问题
/// - 在 SDP 协商前强化编码参数防止分辨率自动降级
class AndroidWebRTCHandler {
  AndroidWebRTCHandler({
    required this.peerConnection,
    required this.localStream,
    required this.localRenderer,
  });

  final RTCPeerConnection? peerConnection;
  final MediaStream? localStream;
  final RTCVideoRenderer localRenderer;

  MediaStreamTrack? _videoTrack;
  bool _isVideoEnabled = false; // Android 默认禁用视频
  String? _currentFacingMode;

  MediaStreamTrack? get videoTrack => _videoTrack;
  bool get isVideoEnabled => _isVideoEnabled;

  void setVideoTrack(MediaStreamTrack track) {
    _videoTrack = track;
    _currentFacingMode ??= 'environment';
    // Android: 默认禁用视频轨道（Android暂不支持视频功能）
    _videoTrack!.enabled = false;
  }

  /// 获取 Android 专用的 Video Transceiver 配置
  ///
  /// Android 策略（华为设备修复版本）：
  /// - active 初始为 true（立即激活，不同于 iOS）
  /// - 添加 degradationPreference 防止自动降级
  /// - 移除 scalabilityMode 避免兼容性问题
  /// - 强制使用高码率和低 scaleResolutionDownBy
  static RTCRtpTransceiverInit getTransceiverInit() {
    return RTCRtpTransceiverInit(
      direction: TransceiverDirection.SendRecv,
      sendEncodings: [
        RTCRtpEncoding(
          active: true, // Android: 立即激活
          maxBitrate: 8000000, // 8 Mbps - 高码率防止降级
          scaleResolutionDownBy: 1, // 强制不缩放
          maxFramerate: 30,
          // 🔑 v2 修复：移除 scalabilityMode 避免华为编码器问题
          // scalabilityMode: 'L1T3',
        ),
      ],
    );
  }

  /// 在 SDP 协商前强制设置编码参数
  ///
  /// 华为设备专用：在 transceiver 创建后、offer 创建前
  /// 再次确认并强化编码参数，防止编码器自动降级
  Future<void> enforceEncodingParametersBeforeOffer(RTCRtpTransceiver transceiver) async {
    logI('[Android] 🎯 [SDP协商前参数强化] 开始强化编码参数...');

    try {
      final sender = transceiver.sender;
      final parameters = sender.parameters;

      // 🔑 详细日志：记录当前参数
      logI('[Android] 🎯 [SDP协商前参数强化] 当前参数: $parameters');

      final encodings = parameters.encodings;
      if (encodings != null && encodings.isNotEmpty) {
        final firstEncoding = encodings.first;

        logI('[Android] 🎯 [SDP协商前参数强化] 当前编码参数:');
        logI('  - active: ${firstEncoding.active}');
        logI('  - maxBitrate: ${firstEncoding.maxBitrate}');
        logI('  - scaleResolutionDownBy: ${firstEncoding.scaleResolutionDownBy}');
        logI('  - maxFramerate: ${firstEncoding.maxFramerate}');
        logI('  - scalabilityMode: ${firstEncoding.scalabilityMode}');

        // 🔑 关键修复：创建强化的编码参数
        final enforcedEncoding = RTCRtpEncoding(
          active: true, // 强制激活
          maxBitrate: 8000000, // 8 Mbps
          scaleResolutionDownBy: 1, // 强制不缩放
          maxFramerate: 30,
          rid: firstEncoding.rid,
          // 不设置 scalabilityMode，让 WebRTC 自动选择
        );

        // 🔑 关键修复：添加 degradationPreference
        final enforcedParams = RTCRtpParameters(
          encodings: [enforcedEncoding],
          degradationPreference: RTCDegradationPreference.MAINTAIN_RESOLUTION,
        );

        await sender.setParameters(enforcedParams);

        logI('[Android] 🎯 [SDP协商前参数强化] ✅ 参数强化完成');
        logI('  - degradationPreference: MAINTAIN_RESOLUTION');
        logI('  - scaleResolutionDownBy: 1.0 (强制不缩放)');
        logI('  - maxBitrate: 8000000');
        logI('  - scalabilityMode: (移除)');
      }
    } catch (e) {
      logE('[Android] 🎯 [SDP协商前参数强化] ❌ 参数强化失败: $e');
    }
  }

  /// Android 切换视频状态
  ///
  /// Android 特定处理：
  /// - 不需要 degradationPreference（iOS 专属）
  /// - 更新编码器 active 状态
  Future<void> toggleVideo() async {
    if (_videoTrack == null) {
      logW('[Android] 视频轨道不存在');
      return;
    }

    final newState = !_isVideoEnabled;
    logI('[Android] 切换视频状态: $_isVideoEnabled -> $newState');

    _isVideoEnabled = newState;
    _videoTrack!.enabled = newState;

    logI('[Android] 视频轨道状态已更新: enabled=$newState');

    if (newState) {
      await _rebindVideoRenderer();
    }

    // Android: 更新编码器 active 状态
    await _updateVideoEncodingActive(newState);

    // Android 不需要 degradationPreference 和质量调整
    logI('[Android] 视频已${newState ? "启用" : "禁用"}');
  }

  /// Android 更新视频编码器 active 状态
  Future<void> _updateVideoEncodingActive(bool isActive) async {
    if (peerConnection == null) {
      logW('[Android] PeerConnection 为空');
      return;
    }

    try {
      final senders = await peerConnection!.getSenders();
      for (final sender in senders) {
        if (sender.track?.kind == 'video') {
          final parameters = sender.parameters;
          final encodings = parameters.encodings;

          if (encodings != null && encodings.isNotEmpty) {
            final firstEncoding = encodings.first;
            if (firstEncoding.active != isActive) {
              final updatedEncoding = RTCRtpEncoding(
                active: isActive,
                maxBitrate: firstEncoding.maxBitrate,
                scaleResolutionDownBy: firstEncoding.scaleResolutionDownBy,
                maxFramerate: firstEncoding.maxFramerate,
                rid: firstEncoding.rid,
                // 🔑 v2 修复：不再设置 scalabilityMode
              );

              await sender.setParameters(
                RTCRtpParameters(encodings: [updatedEncoding]),
              );

              logI('[Android] 编码器状态已更新: active=$isActive');
            }
          }
        }
      }
    } catch (e) {
      logE('[Android] 更新编码器状态失败: $e');
    }
  }

  /// 重新绑定视频渲染器
  Future<void> _rebindVideoRenderer() async {
    try {
      logI('[Android] 🎨 [渲染器重新绑定] 开始重新绑定渲染器...');
      logI('[Android] 🎨 [渲染器重新绑定] 当前尺寸: ${localRenderer.videoWidth}x${localRenderer.videoHeight}');

      // 解除绑定
      localRenderer.srcObject = null;
      await Future.delayed(const Duration(milliseconds: 100));

      // 重新绑定
      localRenderer.srcObject = localStream;
      await Future.delayed(const Duration(milliseconds: 200));

      final newWidth = localRenderer.videoWidth;
      final newHeight = localRenderer.videoHeight;
      logI('[Android] 🎨 [渲染器重新绑定] 新尺寸: $newWidth x $newHeight');
      logI('[Android] 🎨 [渲染器重新绑定] ✅ 渲染器重新绑定完成');
    } catch (e) {
      logE('[Android] 🎨 [渲染器重新绑定] ❌ 重新绑定失败: $e');
    }
  }

  /// Android 摄像头切换
  ///
  /// Android 与 iOS 使用相同的 Helper.switchCamera 方法
  Future<bool> switchCamera() async {
    if (_videoTrack == null) {
      logW('[Android] 视频轨道不存在，无法切换摄像头');
      return false;
    }

    try {
      // 📹 新增：切换前记录当前状态
      final trackSettingsBefore = _videoTrack?.getSettings();
      logI('[Android] 🎥 [摄像头切换] ========== 切换前 ==========');
      logI('[Android] 🎥 [摄像头切换] 当前朝向: $_currentFacingMode');
      logI('[Android] 🎥 [摄像头切换] 轨道设置: $trackSettingsBefore');
      logI('[Android] 🎥 [摄像头切换] 渲染器尺寸: ${localRenderer.videoWidth}x${localRenderer.videoHeight}');
      logI('[Android] 🎥 [摄像头切换] ======================================');

      // 调用 Helper.switchCamera
      final bool result = await Helper.switchCamera(_videoTrack!);

      if (result) {
        // 📹 新增：切换后等待摄像头稳定
        await Future.delayed(const Duration(milliseconds: 300));

        // 📹 新增：切换后验证
        final trackSettingsAfter = _videoTrack?.getSettings();
        logI('[Android] 🎥 [摄像头切换] ========== 切换后 ==========');
        logI('[Android] 🎥 [摄像头切换] Helper.switchCamera 返回: $result');
        logI('[Android] 🎥 [摄像头切换] 轨道设置: $trackSettingsAfter');

        // 📹 新增：重新绑定渲染器（华为设备修复）
        await _rebindVideoRenderer();

        // 等待渲染器更新
        await Future.delayed(const Duration(milliseconds: 200));

        final widthAfter = localRenderer.videoWidth;
        final heightAfter = localRenderer.videoHeight;
        logI('[Android] 🎥 [摄像头切换] 渲染器尺寸: $widthAfter x $heightAfter');

        // 📹 更新朝向状态
        _currentFacingMode = _currentFacingMode == 'environment' ? 'user' : 'environment';

        // 📹 验证切换是否成功（检查渲染器尺寸是否变化）
        if (widthAfter > 0 && heightAfter > 0) {
          // 华为设备：前置摄像头通常是竖屏分辨率，后置是横屏
          logI('[Android] 🎥 [摄像头切换] 新朝向: $_currentFacingMode');
          logI('[Android] 🎥 [摄像头切换] ✅ 摄像头切换成功');
          logI('[Android] 🎥 [摄像头切换] ======================================');
          return true;
        } else {
          logW('[Android] 🎥 [摄像头切换] ⚠️ 渲染器尺寸异常，切换可能失败');
          logI('[Android] 🎥 [摄像头切换] ======================================');
          return false;
        }
      } else {
        logW('[Android] 🎥 [摄像头切换] ⚠️ Helper.switchCamera 返回 false');
        logI('[Android] 🎥 [摄像头切换] ======================================');
        return false;
      }
    } catch (e) {
      logE('[Android] 🎥 [摄像头切换] ❌ 摄像头切换异常: $e');
      logI('[Android] 🎥 [摄像头切换] ======================================');
      return false;
    }
  }

  /// 强制设置视频编码分辨率
  ///
  /// 华为设备专用：在 SDP 协商后，编码器可能会自动降低分辨率
  /// 此方法强制设置编码器参数，确保分辨率保持至少 1280x720
  Future<void> enforceVideoResolution() async {
    if (peerConnection == null || _videoTrack == null) {
      return;
    }

    final currentWidth = localRenderer.videoWidth;
    final currentHeight = localRenderer.videoHeight;

    // 只有当分辨率异常降低时才修正
    if (currentWidth >= 1280) {
      return; // 分辨率正常，无需修正
    }

    logW('[Android] 🎯 [分辨率修正] 检测到分辨率异常: ${currentWidth}x$currentHeight，开始修正...');

    try {
      final senders = await peerConnection!.getSenders();
      for (final sender in senders) {
        if (sender.track?.kind == 'video') {
          final parameters = sender.parameters;
          final encodings = parameters.encodings;

          if (encodings != null && encodings.isNotEmpty) {
            final firstEncoding = encodings.first;

            // 强制设置 scaleResolutionDownBy = 1 (不缩放)
            final updatedEncoding = RTCRtpEncoding(
              active: firstEncoding.active,
              maxBitrate: firstEncoding.maxBitrate ?? 8000000,
              scaleResolutionDownBy: 1.0, // 🔑 关键：强制不缩放
              maxFramerate: firstEncoding.maxFramerate ?? 30,
              rid: firstEncoding.rid,
              // 🔑 v2 修复：不再设置 scalabilityMode
            );

            await sender.setParameters(
              RTCRtpParameters(encodings: [updatedEncoding]),
            );

            logI('[Android] 🎯 [分辨率修正] ✅ 已强制设置 scaleResolutionDownBy=1');

            // 等待编码器应用新参数
            await Future.delayed(const Duration(milliseconds: 500));

            // 重新绑定渲染器以应用更改
            await _rebindVideoRenderer();

            final newWidth = localRenderer.videoWidth;
            final newHeight = localRenderer.videoHeight;
            logI('[Android] 🎯 [分辨率修正] 修正后分辨率: ${newWidth}x$newHeight');
          }
        }
      }
    } catch (e) {
      logE('[Android] 🎯 [分辨率修正] ❌ 修正失败: $e');
    }
  }
}
