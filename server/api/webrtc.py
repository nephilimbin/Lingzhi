import asyncio
import os
import queue
import time
import traceback
from typing import Any, Dict, Optional

from config.logger import setup_logging
from core.context.event_bus import Event
from core.context.event_types import EventTypes
from core.global_services import GlobalServices
from core.models.message_models import (
    AudioParams,
    AudioPlaybackStatus,
    MessageInfo,
    PlaybackMode,
    PlaybackState,
    SessionInfo,
)
from core.session.session_context import SessionContext
from core.utils.util import set_unique_id
import cv2
from fastrtc import AsyncAudioVideoStreamHandler, Stream, wait_for_item
from fastrtc.utils import get_current_context
import numpy as np

TAG = __name__

# WebRTC音频流采样率 - 使用16000Hz以匹配ASR和项目标准
SAMPLE_RATE = 16000


class WebrtcStreamHandler(AsyncAudioVideoStreamHandler):
    """
    FastRTC Stream Handler 支持音视频处理
    保留原有的业务逻辑，扩展视频接收能力
    """

    def __init__(self):
        super().__init__(
            expected_layout="mono",
            output_sample_rate=SAMPLE_RATE,
            input_sample_rate=SAMPLE_RATE,
        )
        self.webrtc_tts_audio_output_queue: queue.Queue = None
        self.webrtc_vlm_video_queue: queue.Queue = None
        self.audio_frame_count = 0
        self.logger = setup_logging()

        # 会话ID
        self.webrtc_id = None

        # 会话上下文
        self.session_context: SessionContext = None
        self.state_manager = None  # 延迟到 start_up() 中设置

        # 视频相关属性
        self.video_frame_count = 0  # 视频帧计数器
        self.receive_video_queue: asyncio.Queue = asyncio.Queue()

    def copy(self):
        return WebrtcStreamHandler()

    async def send_audio_listen_event(self):
        """
        发送音频监听事件

        构建MessageInfo，严格按照项目架构要求：
        - event_type: "request.listen"
        - transport: "webrtc"
        - audio_params.format: "ndarray"
        - playback_mode: PlaybackMode.AUTO

        发布事件到event_bus
        """
        try:
            if not self.session_context:
                self.logger.bind(tag=TAG).warning("会话上下文未初始化，无法发送音频监听事件")
                return

            event_bus = self.session_context.event_bus
            if not event_bus:
                self.logger.bind(tag=TAG).warning("事件总线未初始化，无法发送音频监听事件")
                return

            # 生成唯一的会话请求ID
            session_request_id = set_unique_id("webrtc")

            # 构建音频参数
            audio_params = AudioParams(format="ndarray", sample_rate=SAMPLE_RATE)
            # 构建会话信息
            audio_playback_status = AudioPlaybackStatus(state=PlaybackState.START, mode=PlaybackMode.AUTO)
            session_info = SessionInfo(
                session_id=self.session_context.session_id,
                modalities=["audio"],
                audio_params=audio_params,
                audio_input_format="ndarray",
                audio_output_format="ndarray",
                session_request_id=session_request_id,
                audio_playback_status=audio_playback_status,
            )

            # 构建消息信息
            message_info = MessageInfo(type="request.listen", transport="webrtc", session=session_info)

            # 创建事件
            event = Event(
                event_type=EventTypes.AUDIO_LISTEN_REQUESTED,
                session_id=self.session_context.session_id,
                data=message_info,
            )

            # 发布事件到事件总线
            await event_bus.publish(event)

            self.logger.bind(tag=TAG).info(
                f"成功发送音频监听事件: session_id={self.session_context.session_id}, "
                f"session_request_id={session_request_id}, format=ndarray"
            )

        except Exception as e:
            self.logger.bind(tag=TAG).error(f"发送音频监听事件时发生错误: {e}")

    async def send_audio_bytes_parse_event(self, frame: tuple[int, np.ndarray]):
        """
        发送音频字节解析事件 - 与WebSocket处理方式保持一致

        按照event_dispatcher.py中_route_message的相同模式处理音频字节流：
        1. 获取当前会话请求ID
        2. 使用MessageInfo.create_audio_bytes_message_info创建消息
        3. 发布AUDIO_BYTES_PARSE_REQUESTED事件

        这样确保WebRTC和WebSocket音频流处理逻辑完全统一
        """
        try:
            if not self.session_context:
                self.logger.bind(tag=TAG).warning("会话上下文未初始化，无法发送音频字节解析事件")
                return

            event_bus = self.session_context.event_bus
            if not event_bus:
                self.logger.bind(tag=TAG).warning("事件总线未初始化，无法发送音频字节解析事件")
                return

            # 获取音频帧数据 - 与event_dispatcher.py保持一致的处理方式
            _, audio_data = frame

            # 获取当前会话请求ID - 与WebSocket处理方式一致
            current_session_request_id = self.session_context.state_manager.current_session_request_id

            # 使用与WebSocket相同的消息创建方法
            message_info = MessageInfo.create_audio_bytes_message_info(audio_data, current_session_request_id)

            # 创建事件 - 与event_dispatcher.py完全一致
            event = Event(
                event_type=EventTypes.AUDIO_BYTES_PARSE_REQUESTED,
                session_id=self.session_context.session_id,
                data=message_info,
            )

            # 发布事件到事件总线
            await event_bus.publish(event)

        except Exception as e:
            self.logger.bind(tag=TAG).error(f"发送音频字节解析事件时发生错误: {e}")

    async def start_up(self):
        """Start handler"""
        try:
            # 获取FastRTC上下文和webrtc_id
            current_context = get_current_context()
            self.webrtc_id = current_context.webrtc_id
            self.logger.bind(tag=TAG).info(f"🚀 WebRTC Streaming handler started: {self.webrtc_id}")

            # 直接获取会话上下文 - 前端确保webrtc_id与session_id一致
            self.session_context = GlobalServices.get_active_session_context(self.webrtc_id)

            if self.session_context:
                # 初始化 state_manager
                self.state_manager = self.session_context.state_manager
                # 发送音频监听事件
                await self.send_audio_listen_event()
                # 从session的statemananger中接收队列
                self.webrtc_tts_audio_output_queue = self.state_manager.webrtc_tts_audio_output_queue
                # 获取vlm视频帧接收队列
                self.webrtc_vlm_video_queue: queue.Queue = self.state_manager.webrtc_vlm_video_queue
                # 创建 VLM 文件夹路径
                self.vlm_dir = os.path.join(self.session_context.client_session_dir, "vlm")
                os.makedirs(self.vlm_dir, exist_ok=True)
                self.last_video_save_time = 0  # 上次保存视频帧的时间戳（秒）
            else:
                self.logger.bind(tag=TAG).warning(f"⚠️ WebRTC连接已建立，但无法获取会话上下文: {self.webrtc_id}")

        except Exception as e:
            self.logger.bind(tag=TAG).error(f"WebRTC启动过程中发生错误: {e}", exc_info=True)

    async def receive(self, frame: tuple[int, np.ndarray]) -> None:
        """Receive audio frame and perform streaming speech recognition"""
        try:
            self.audio_frame_count += 1

            # 发送音频字节解析事件
            await self.send_audio_bytes_parse_event(frame)

        except Exception as e:
            self.logger.error(f"❌ Error processing streaming audio frame: {e}")

    async def emit(self) -> Any:
        """
        输出音频处理
        注意：output_queue接收的是一个元组。
        使用 asyncio.to_thread() 线程安全地访问 queue.Queue。
        """
        try:
            if not self.webrtc_tts_audio_output_queue:
                return None

            if self.state_manager.tts_tasks_stop:
                return None

            try:
                result = self.webrtc_tts_audio_output_queue.get_nowait()
                if isinstance(result, tuple) and len(result) >= 4:
                    sample_rate, audio_array, session_request_id, array_index = result[:4]
                    # self.logger.bind(tag=TAG).info(f"✅ 收到音频帧{array_index}")
                    return (sample_rate, audio_array)
            except queue.Empty:
                return None
        except Exception:
            self.logger.bind(tag=TAG).error(f"WebRTC emit方法出错: {traceback.format_exc()}")
            return None

    # === 视频接收处理 ===
    async def video_receive(self, frame: np.ndarray) -> None:
        """
        接收视频帧 - 保存为 JPEG 图片

        Args:
            frame: BGR24 格式的 numpy 数组，shape=(height, width, 3)
        """
        try:
            self.video_frame_count += 1
            # 增强日志：显示帧的详细信息，用于调试视频传输问题
            # if frame is not None:
            #     self.logger.bind(tag=TAG).info(
            #         f"🎥 Received video frame #{self.video_frame_count}: "
            #         f"shape={frame.shape}, dtype={frame.dtype}, "
            #         f"size={frame.shape[1]}x{frame.shape[0]}"
            #     )

            if frame is not None:
                # 放入接收视频队列，用于对齐发送。
                self.receive_video_queue.put_nowait(frame)

                # 生成文件名：时间戳.jpeg
                timestamp = int(time.time() * 1000)  # 毫秒级时间戳
                filename = f"{timestamp}.jpeg"
                filepath = os.path.join(self.vlm_dir, filename)
                # 保存为 JPEG 格式
                cv2.imwrite(filepath, frame)

            # 根据用户说话开始截取视频图片
            if self.state_manager.client_first_have_voice:
                # 放入待处理视频帧队列
                current_time = time.time()
                if current_time - self.last_video_save_time >= 1:
                    self.last_video_save_time = current_time
                    # 放入待处理vlm队列
                    self.webrtc_vlm_video_queue.put_nowait(filepath)

        except Exception as e:
            self.logger.bind(tag=TAG).error(f"处理视频帧时发生错误: {e}")

    async def video_emit(self) -> np.ndarray | None:
        """
        输出视频帧 - 发送测试视频帧以触发 iOS WebRTC 的视频传输

        iOS WebRTC 有一个特性：只有当它检测到远端也在发送视频时，
        才会开始发送自己的视频（对称性行为）。

        Returns:
            返回一个简单的测试视频帧（黑色画面），表示发送视频到前端
        """
        try:
            frame = await wait_for_item(self.receive_video_queue, 0.01)
            # 这个日志只是表示 video_emit 被调用，不代表收到前端视频
            # 真正的接收日志在 video_receive 方法中
            # self.logger.bind(tag=TAG).debug(f"[video_emit] 尝试从队列获取视频帧，当前计数: {self.video_frame_count}")
            # 不论是否开始接收frame，都需要返回一个图片用于创建视频通道，针对IOS平台。
            if frame is not None:
                # 暂不需要双向发送，节省流量发送小图片
                return np.zeros((100, 100, 3), dtype=np.uint8)
            else:
                return np.zeros((100, 100, 3), dtype=np.uint8)
                # return np.zeros((1920, 1080, 3), dtype=np.uint8)

        except Exception as e:
            self.logger.bind(tag=TAG).error(f"生成测试视频帧时出错: {e}")
            return None

    async def shutdown(self):
        """关闭webrtc流传输"""
        try:
            # 设置TTS任务状态
            self.state_manager.update_state(tts_tasks_stop=True)

            # 发送取消在执行的任务指令
            await self.session_context.event_bus.publish(
                Event(
                    event_type=EventTypes.SESSION_TASKS_CANCEL_REQUESTED,
                    session_id=self.session_context.session_id,
                    data={
                        "task_types": [],
                    },
                )
            )

            # 清理其他资源
            self.webrtc_id = None
            self.audio_frame_count = 0

            # 清理输出队列
            while not self.webrtc_tts_audio_output_queue.empty():
                try:
                    self.webrtc_tts_audio_output_queue.get_nowait()
                    self.webrtc_tts_audio_output_queue.task_done()
                except queue.Empty:
                    break
            # 重置队列引用
            self.webrtc_tts_audio_output_queue = None

            # 清理所有未完成的异步任务，避免aioice的STUN重试异常
            tasks = [t for t in asyncio.all_tasks() if t is not asyncio.current_task()]
            for task in tasks:
                if task.get_name() == "Transaction.__retry" or "aioice" in str(task.get_coro()):
                    self.logger.bind(tag=TAG).info(f"取消aioice相关任务: {task.get_name()}")
                    task.cancel()
                    try:
                        await task
                    except asyncio.CancelledError:
                        pass
                    except Exception as e:
                        self.logger.bind(tag=TAG).warning(f"取消任务时出错: {e}")

            self.logger.bind(tag=TAG).info("WebRTC会话资源清理完成")

        except Exception as e:
            self.logger.bind(tag=TAG).error(f"清理会话资源时发生错误: {e}", exc_info=True)


def create_rtc_configuration(config: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    """
    创建支持 coturn 中继的 RTC 配置，参考 OpenAvatarChat 项目的实现
    支持relay中继功能测试

    从配置文件读取 ICE 服务器配置，不使用硬编码凭据

    Args:
        config: 可选的配置字典，如果为 None 则从 ServerConfiger 加载

    Returns:
        RTC 配置字典
    """
    from config.server_config import ServerConfiger

    if config is None:
        config = ServerConfiger.load_config()

    webrtc_config = config.get("server", {}).get("webrtc", {})

    # 从配置文件读取 ice_servers，不使用硬编码凭据
    # 如果配置文件中没有配置，使用公开的 STUN 服务器（不需要凭据）
    ice_servers = webrtc_config.get("ice_servers", [{"urls": ["stun:stun.l.google.com:19302"]}])

    return {
        "iceServers": ice_servers,
        "iceCandidatePoolSize": webrtc_config.get("ice_candidate_pool_size", 4),
        "iceTransportPolicy": webrtc_config.get("ice_transport_policy", "all"),
        "bundlePolicy": webrtc_config.get("bundle_policy", "max-bundle"),
        "rtcpMuxPolicy": webrtc_config.get("rtcp_mux_policy", "require"),
    }


def create_webrtc_stream():
    """Create Fixed FastRTC stream - 保留原有配置，增加aioice异常修复和调试补丁"""

    # Create stream handler - 保持原有的业务逻辑
    handler = WebrtcStreamHandler()

    # 使用原有的配置
    rtc_configuration = create_rtc_configuration()

    # 创建 FastRTC stream with 修复版本配置
    stream = Stream(
        handler=handler,
        mode="send-receive",
        modality="audio-video",
        concurrency_limit=2,
        time_limit=300,
        rtc_configuration=rtc_configuration,
        server_rtc_configuration=rtc_configuration,
    )

    # 应用WebRTC清理，修复aioice STUN重试异常
    from api.webrtc_cleanup import WebRTCCleanup

    WebRTCCleanup.patch_stream_clean_up(stream)

    return stream
