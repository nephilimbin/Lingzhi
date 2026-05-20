import asyncio
import traceback
from typing import TYPE_CHECKING

from config.logger import setup_logging
from core.context.event_bus import Event
from core.context.event_types import EventTypes
from core.models.message_models import ChatMode, MessageInfo

if TYPE_CHECKING:
    from core.session.session_context import SessionContext

TAG = __name__
logger = setup_logging()


class ClientMuteHandler:
    """Handles incoming mute messages, adapted from original handleMuteMessage."""

    def __init__(self, context: "SessionContext"):
        self.context = context
        self.logger = setup_logging()
        self.session_request_id = ""
        if hasattr(context, "event_bus") and context.event_bus:
            self.event_bus = context.event_bus
            self._subscribe_to_events()

    def _subscribe_to_events(self):
        """订阅文本消息相关事件"""
        if self.event_bus:
            self.event_bus.subscribe(EventTypes.CLIENT_MUTE_REQUESTED, self.handle_mute_event)

    async def handle_mute_event(self, event: Event):
        """新增：事件驱动的文本处理方法"""
        if not self.event_bus:
            return

        try:
            # 获取MessageInfo对象
            request_message_info: MessageInfo = event.data
            chat_mode = request_message_info.session.chat_mode

            # 创建可取消的任务
            task = asyncio.create_task(self.handle(chat_mode))
            await task

        except Exception as e:
            self.logger.bind(tag=TAG).error(f"事件驱动文本处理错误: {e}", exc_info=True)

    async def handle(self, chat_mode: str):
        """处理打断消息 - 用户主动中断，需要设置client_abort状态来暂停TTS等任务"""
        try:
            # 设置客户端静音状态
            self.context.state_manager.update_state(chat_mode=chat_mode)
            self.logger.debug(f"[ClientMuteHandler] 设置静音状态: state={chat_mode}")

            # 发布客户端静音事件，让CancellationManager处理音频输出相关任务取消
            await self.event_bus.publish(
                Event(
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
            )

            # 清理服务端讲话状态
            self.context.state_manager.reset_llm_task_states()

            # 清理队列状态
            self.context.tts_pipeline.clear_audio_tts_queue()
            self.context.tts_pipeline.clear_audio_play_queue()

            # 清空ASR音频数据
            self.context.state_manager.reset_asr_task_states()

            # 发送TTS停止消息（最后发送，确保状态已清理）
            if self.context.state_manager.chat_mode == ChatMode.MUTE_MODE:
                await self.context.output_processor.send_tts_stop_message(self.session_request_id)

            self.logger.debug("中止处理完成，已清理相关状态")
        except Exception:
            self.logger.error(f"清理队列时出错: {traceback.format_exc()}")
