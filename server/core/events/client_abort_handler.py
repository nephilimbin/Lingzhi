import asyncio
import traceback
from typing import TYPE_CHECKING

from config.logger import setup_logging
from core.context.event_bus import Event
from core.context.event_types import EventTypes
from core.models.message_models import PlaybackMode

if TYPE_CHECKING:
    from core.session.session_context import SessionContext

TAG = __name__
logger = setup_logging()


class ClientAbortHandler:
    """
    用户打断操作的处理类
    """

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
            self.event_bus.subscribe(EventTypes.CLIENT_ABORT_REQUESTED, self.handle_abort_event)

    async def handle_abort_event(self, event: Event):
        """新增：事件驱动的文本处理方法"""
        if not self.event_bus:
            return

        try:
            # 获取MessageInfo对象
            # request_message_info: MessageInfo = event.data

            # 创建可取消的任务
            task = asyncio.create_task(self.handle())
            await task

        except Exception:
            self.logger.bind(tag=TAG).error(f"事件驱动文本处理错误: {traceback.format_exc()}")

    async def handle(self):
        """处理打断消息 - 用户主动中断，需要设置client_abort状态来暂停TTS等任务"""

        # 发布客户端中断请求事件
        await self.event_bus.publish(
            Event(
                event_type=EventTypes.SESSION_TASKS_CANCEL_REQUESTED,
                session_id=self.context.session_id,
                data={"task_types": []},
            )
        )

        try:
            self.context.state_manager.reset_llm_task_states()
            self.context.tts_pipeline.stop_tts_pipeline_threads()
            self.context.state_manager.reset_asr_task_states()

            # 发送TTS停止消息（最后发送，确保状态已清理）
            if self.context.state_manager.client_listen_mode == PlaybackMode.MANUAL:
                await self.context.output_processor.send_tts_stop_message(self.session_request_id)
            elif self.context.state_manager.client_listen_mode == PlaybackMode.AUTO:
                # 自动模式需重启ASR服务状态
                self.context.state_manager.restart_auto_mode_asr_task_states()
        except Exception:
            logger.error(f"中断时出错: {traceback.format_exc()}")
