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


class ClientHandshakeHandler:
    """Handles incoming hello messages, adapted from original handleHelloMessage."""

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
            self.event_bus.subscribe(EventTypes.CLIENT_HANDSHAKE_REQUESTED, self.handle_handshake_event)

    async def handle_handshake_event(self, event: Event):
        """新增：事件驱动的文本处理方法"""
        if not self.event_bus:
            return

        try:
            # 获取MessageInfo对象
            request_message_info: MessageInfo = event.data
            chat_mode = request_message_info.session.chat_mode
            # 创建任务
            task = asyncio.create_task(self.handle(chat_mode))
            # 等待任务完成
            await task

        except Exception:
            self.logger.bind(tag=TAG).error(f"事件驱动握手处理错误: {traceback.format_exc()}")

    async def handle(self, chat_mode: str = ChatMode.USUAL_MODE):
        """发送欢迎消息,传递初始会话id"""

        # 设置初始化的聊天模式
        self.context.state_manager.update_state(chat_mode=chat_mode)

        # 发送握手响应消息
        await self.context.output_processor.send_handshake_message(self.session_request_id, chat_mode)
