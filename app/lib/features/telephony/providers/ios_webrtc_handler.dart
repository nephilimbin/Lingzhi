import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:ai_assistant/core/utils/app_logger.dart';

/// iOS WebRTC 处理器
///
/// 职责：
/// - 管理 iOS 平台的 WebRTC 视频逻辑
/// - 保持原有逻辑，包括动态质量调整
/// - 支持 degradationPreference 配置
class IOSWebRTCHandler {
  IOSWebRTCHandler({
    required this.peerConnection,
    required this.localStream,
    required this.localRenderer,
  });

  final RTCPeerConnection? peerConnection;
  final MediaStream? localStream;
  final RTCVideoRenderer localRenderer;

  MediaStreamTrack? _videoTrack;
  bool _isVideoEnabled = false;
  String? _currentFacingMode; // 当前摄像头朝向

  MediaStreamTrack? get videoTrack => _videoTrack;
  bool get isVideoEnabled => _isVideoEnabled;

  void setVideoTrack(MediaStreamTrack track) {
    _videoTrack = track;
    // 初始化时记录当前摄像头朝向（默认后置）
    _currentFacingMode ??= 'environment';
  }

  /// 获取 iOS 专用的 Video Transceiver 配置
  ///
  /// iOS 策略：
  /// - active 初始为 false（等待对称触发）
  /// - 支持 degradationPreference 配置
  static RTCRtpTransceiverInit getTransceiverInit() {
    return RTCRtpTransceiverInit(
      direction: TransceiverDirection.SendRecv,
      sendEncodings: [
        RTCRtpEncoding(
          active: false, // 等待对称触发
          maxBitrate: 8000000, // 8 Mbps
          scaleResolutionDownBy: 1, // 原始分辨率
          maxFramerate: 30, // 30fps
          rid: 'high',
        ),
      ],
    );
  }

  /// iOS 切换视频状态
  ///
  /// 保持原有逻辑：
  /// - 更新编码器 active 状态
  /// - 调用 _adaptVideoQuality() 进行质量调整
  Future<void> toggleVideo() async {
    if (_videoTrack == null) {
      logW('[iOS] 视频轨道不存在');
      return;
    }

    final newState = !_isVideoEnabled;
    logI('[iOS] 切换视频状态: $_isVideoEnabled -> $newState');

    _isVideoEnabled = newState;
    _videoTrack!.enabled = newState;

    logI('[iOS] 视频轨道状态已更新: enabled=$newState');

    if (newState) {
      await _rebindVideoRenderer();
    }

    // iOS: 更新编码器 active 状态
    await _updateVideoEncodingActive(newState);

    // iOS: 调用质量调整（保持原有逻辑）
    if (newState) {
      await _adaptVideoQuality();
    }

    logI('[iOS] 视频已${newState ? "启用" : "禁用"}');
  }

  /// iOS 更新视频编码器 active 状态
  Future<void> _updateVideoEncodingActive(bool isActive) async {
    if (peerConnection == null) {
      logW('[iOS] PeerConnection 为空');
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
              );

              await sender.setParameters(
                RTCRtpParameters(encodings: [updatedEncoding]),
              );

              logI('[iOS] 编码器状态已更新: active=$isActive');
            }
          }
        }
      }
    } catch (e) {
      logE('[iOS] 更新编码器状态失败: $e');
    }
  }

  /// iOS 视频质量调整
  ///
  /// 保持原有逻辑：scaleResolutionDownBy = 1.5
  Future<void> _adaptVideoQuality() async {
    if (peerConnection == null) {
      logD('[iOS] PeerConnection为空');
      return;
    }

    if (!_isVideoEnabled) {
      logD('[iOS] 视频未启用');
      return;
    }

    try {
      const double scaleResolutionDownBy = 1.5; // iOS 原有配置
      const int maxFramerate = 30;
      const int maxBitrate = 8000000;
      final RTCDegradationPreference degradationPreference =
          RTCDegradationPreference.MAINTAIN_RESOLUTION;

      logI('[iOS] 应用视频质量调整...');

      final senders = await peerConnection!.getSenders();
      for (final sender in senders) {
        if (sender.track?.kind == 'video') {
          final parameters = sender.parameters;
          final encodings = parameters.encodings;

          if (encodings != null && encodings.isNotEmpty) {
            final currentEncoding = encodings.first;

            final updatedEncoding = RTCRtpEncoding(
              active: currentEncoding.active,
              maxBitrate: maxBitrate,
              scaleResolutionDownBy: scaleResolutionDownBy,
              maxFramerate: maxFramerate,
              rid: currentEncoding.rid,
            );

            final updatedParameters = RTCRtpParameters(
              encodings: [updatedEncoding],
              degradationPreference: degradationPreference,
            );

            await sender.setParameters(updatedParameters);
            logI('[iOS] 视频编码参数已应用');
          }
        }
      }
    } catch (e) {
      logE('[iOS] 应用视频参数失败: $e');
    }
  }

  /// 重新绑定视频渲染器
  Future<void> _rebindVideoRenderer() async {
    try {
      localRenderer.srcObject = null;
      await Future.delayed(const Duration(milliseconds: 50));
      localRenderer.srcObject = localStream;
      logI('[iOS] 视频渲染器已重新绑定');
    } catch (e) {
      logE('[iOS] 重新绑定视频渲染器失败: $e');
    }
  }

  /// iOS 摄像头切换
  ///
  /// iOS 可以使用 Helper.switchCamera() 方法
  /// 也可以使用 replaceTrack 方法保持与 Android 一致
  Future<bool> switchCamera() async {
    if (_videoTrack == null) {
      logW('[iOS] 视频轨道不存在，无法切换摄像头');
      return false;
    }

    try {
      // 使用 flutter_webrtc 的 Helper.switchCamera
      final bool result = await Helper.switchCamera(_videoTrack!);
      if (result) {
        // 更新摄像头朝向状态
        _currentFacingMode = _currentFacingMode == 'environment' ? 'user' : 'environment';
        logI('[iOS] ✅ 摄像头已切换，当前朝向: $_currentFacingMode');
        return true;
      } else {
        logW('[iOS] ⚠️ 摄像头切换失败');
        return false;
      }
    } catch (e) {
      logE('[iOS] ❌ 摄像头切换异常: $e');
      return false;
    }
  }
}
