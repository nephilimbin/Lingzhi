import asyncio
import traceback
from typing import TYPE_CHECKING

from config.logger import setup_logging
from core.context.event_bus import Event
from core.context.event_types import EventTypes
from core.models.message_models import (
    MessageInfo,
    PlaybackMode,
    PlaybackState,
    RequestParser,  # 导入新的消息API
)

# 使用TYPE_CHECKING来避免循环导入
if TYPE_CHECKING:
    from core.session.session_context import SessionContext

TAG = __name__


class AudioListenHandler:
    """Handles incoming text messages, adapted from original handleTextMessage."""

    def __init__(self, context: "SessionContext"):
        self.context = context
        self.logger = setup_logging()
        self.session_request_id = ""

        # 新增：事件总线支持
        if hasattr(context, "event_bus") and context.event_bus:
            self.event_bus = context.event_bus
            self._subscribe_to_events()

    def _subscribe_to_events(self):
        """订阅文本消息相关事件"""
        if self.event_bus:
            self.event_bus.subscribe(EventTypes.AUDIO_LISTEN_REQUESTED, self.handle_audio_listen_event)

    async def handle_audio_listen_event(self, event: Event):
        """处理音频监听请求事件"""
        if not self.event_bus:
            return

        try:
            # 获取MessageInfo对象
            request_message_info: MessageInfo = event.data
            message = request_message_info.to_dict()  # 将整个请求信息转为字符串

            # 创建可取消的任务
            task = asyncio.create_task(self.handle(message))

            # 直接使用CancellationManager注册任务
            cancellable_task = await self.context.cancellation_manager.register_task(
                session_id=self.context.session_id,
                task=task,
                task_type=self.context.cancellation_manager.task_types.AUDIO_ASR_REGISTER_TASK,
            )

            try:
                await task

                # 取消注册的任务
                if cancellable_task:
                    cancellable_task.cancel()

            except asyncio.CancelledError:
                self.logger.bind(tag=TAG).info("音频监听任务被取消")
                raise

        except Exception as e:
            self.logger.bind(tag=TAG).error(f"事件驱动文本处理错误: {e}", exc_info=True)

    async def handle(self, message: str):
        """处理音频监听消息"""

        try:
            # 处理request.listen消息类型（音频相关）
            message_info = RequestParser.parse_request(message)

            # 获取会话信息
            if message_info.session:
                audio_params = message_info.session.audio_params
                playback_status = message_info.session.audio_playback_status.state
                playback_status_mode = message_info.session.audio_playback_status.mode
                input_audio_transport_type = message_info.transport

                self.logger.bind(tag=TAG).debug(f"处理listen事件: 播放={playback_status}, 模式={playback_status_mode}")

                # 保存音频参数到状态管理器
                if audio_params:
                    updates = {
                        "current_session_request_id": self.session_request_id,
                        "input_audio_format": audio_params.format,
                        "input_audio_sample_rate": audio_params.sample_rate,
                        "input_audio_channels": audio_params.channels,
                        "input_audio_frame_duration": audio_params.frame_duration,
                        "input_audio_has_started": True,  # 标志开始准备接收的音频参数，初始化解析器使用。
                        "input_audio_transport_type": input_audio_transport_type,
                    }
                    self.context.state_manager.update_state(**updates)
                else:
                    raise ValueError("音频参数不能为空")

                # 处理开始/停止监听信号
                if playback_status == PlaybackState.START:
                    await self._update_listen_states_for_start(playback_status_mode)
                elif playback_status == PlaybackState.STOP:
                    await self._update_listen_states_for_stop(playback_status_mode)
                else:
                    self.logger.bind(tag=TAG).debug(f"收到其他未知播放状态：{playback_status}")

        except Exception:
            self.logger.bind(tag=TAG).error(f"处理listen事件时出错: {traceback.format_exc()}")
            await self.context.output_processor.send_error_message("音频监听处理失败，请重试。")

    async def _update_listen_states_for_start(self, mode: str):
        """更新监听开始状态"""
        try:
            event = Event(
                event_type=EventTypes.SESSION_TASKS_CANCEL_REQUESTED,
                session_id=self.context.session_id,
                data={
                    "session_request_id": self.session_request_id,
                    "task_types": [
                        self.context.cancellation_manager.task_types.AUDIO_TTS_OUTPUT_TASK,
                        self.context.cancellation_manager.task_types.AUDIO_TTS_PROCESS_TASK,
                    ],
                },
            )
            await self.event_bus.publish(event=event)

            # 清理服务端讲话状态
            self.context.state_manager.reset_llm_task_states()
            self.context.tts_pipeline.stop_tts_pipeline_threads()

            # 关闭旧ASR识别器，防止新音频发送到已停止的识别器
            if hasattr(self.context.asr, "close"):
                try:
                    self.context.asr.close()
                except Exception:
                    pass

            self.context.state_manager.reset_asr_task_states()

            # 更新初始音频播放状态
            updates = {
                "client_listen_mode": mode,
                "client_have_voice": True,
                "client_voice_stop": False,
            }

            # manual模式下，重置VAD相关状态
            if mode == PlaybackMode.AUTO:
                updates["client_have_voice_last_time"] = 0.0

            self.context.state_manager.update_state(**updates)
        except Exception as e:
            self.logger.bind(tag=TAG).error(f"更新监听音频开始状态时出错: {e}", exc_info=True)
            raise

    async def _update_listen_states_for_stop(self, mode: str):
        """更新监听停止状态"""
        try:
            # 实时对话模式，还原用户说话状态
            if mode == PlaybackMode.AUTO:
                updates = {"client_have_voice": False, "client_voice_stop": False}
                self.context.state_manager.update_state(**updates)

            # 单次语音对话模式，要发送一帧空音频数据，音频事件会捕获处理结束。否则手动无法结束。
            if mode == PlaybackMode.MANUAL:
                updates = {"client_have_voice": True, "client_voice_stop": True}
                self.context.state_manager.update_state(**updates)
                asr_audio = self.context.state_manager.asr_audio_queue
                if len(asr_audio) > 0:
                    event = Event(
                        event_type=EventTypes.AUDIO_BYTES_PARSE_REQUESTED,
                        session_id=self.context.session_id,
                        data=MessageInfo.create_audio_bytes_message_info(
                            audio_source=b"",  # 发送空音频数据，音频事件会捕获处理结束。否则手动无法结束。
                            session_request_id=self.session_request_id,
                        ),
                    )
                    await self.context.event_bus.publish(event)

        except Exception as e:
            self.logger.bind(tag=TAG).error(f"更新监听音频停止状态时出错: {e}", exc_info=True)
            raise
