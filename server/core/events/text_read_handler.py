import asyncio
import traceback
from typing import TYPE_CHECKING

from config.logger import setup_logging
from core.context.event_bus import Event
from core.context.event_types import EventTypes
from core.models.message_models import (
    MessageInfo,
    RequestParser,  # 导入新的消息API
)

# 使用TYPE_CHECKING来避免循环导入
if TYPE_CHECKING:
    from core.session.session_context import SessionContext

TAG = __name__


class TextReadHandler:
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
            self.event_bus.subscribe(EventTypes.TEXT_READ_REQUESTED, self.handle_text_event)

    async def handle_text_event(self, event: Event):
        """新增：事件驱动的文本处理方法"""
        try:
            # 获取MessageInfo对象
            request_message_info: MessageInfo = event.data
            message = request_message_info.to_dict()

            # 创建可取消的任务
            task = asyncio.create_task(self.handle(message=message))

            # 注册可取消任务
            cancellable_task = await self.context.cancellation_manager.register_task(
                session_id=self.context.session_id,
                task=task,
                task_type=self.context.cancellation_manager.task_types.TEXT_READ_TASK,
            )

            try:
                await task

                # 取消注册的可取消任务
                if cancellable_task:
                    cancellable_task.cancel()

            except asyncio.CancelledError:
                self.logger.bind(tag=TAG).info(f"文本处理任务被取消: {message}")
                raise
        except Exception as e:
            self.logger.bind(tag=TAG).error(f"事件驱动文本处理错误: {e}", exc_info=True)

    async def handle(self, message):
        """处理文本消息"""

        try:
            # 清理服务端讲话状态
            event = Event(
                event_type=EventTypes.SESSION_TASKS_CANCEL_REQUESTED,
                session_id=self.context.session_id,
                data={
                    "task_types": [
                        self.context.cancellation_manager.task_types.AUDIO_ASR_PROCESS_TASK,
                        self.context.cancellation_manager.task_types.AUDIO_TTS_PROCESS_TASK,
                        self.context.cancellation_manager.task_types.AUDIO_TTS_OUTPUT_TASK,
                    ],
                },
            )
            await self.event_bus.publish(event=event)
            self.context.tts_pipeline.stop_tts_pipeline_threads()
            self.context.state_manager.reset_llm_task_states()

            # 使用新的RequestParser解析消息
            message_info = RequestParser.parse_request(message)
            msg_type = message_info.type
            if msg_type == "request.read":
                # 获取文本内容和会话信息
                request_text = message_info.session.text_source
                transport_type = message_info.transport  # 获取传输类型

                if request_text:
                    # 保存传输类型到状态管理器（TTS播放需要）
                    self.context.state_manager.update_state(input_audio_transport_type=transport_type)
                    # 处理文本输入
                    await self.context.chat_processor.process_client_chat(
                        request_text, source="text", session_request_id=self.session_request_id
                    )
                else:
                    await self.context.output_processor.send_error_message("无法解析文本内容, 请检查前端发送的数据格式")
        except Exception:
            self.logger.bind(tag=TAG).error(f"文本处理错误: {traceback.format_exc()}")
            await self.context.output_processor.send_error_message("文本处理异常")
