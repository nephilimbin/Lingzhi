"""
消息分发器模块 - 专注于消息分发和事件任务发布

该模块提供高性能的消息分发服务，负责：
1. 处理各种类型的消息（JSON、字节等）
2. 将消息路由到对应的事件处理器
3. 管理事件处理器的生命周期
4. 统一的消息预处理和状态管理

核心优化特性：
- 零循环开销：直接映射，消除O(n)遍历
- 类型优先：先判断消息类型，减少无效检查
- 精确匹配：每个消息类型只检查对应的处理器
- 映射表优化：使用字典映射消除多个方法调用

使用示例：
    dispatcher = EventDispatcher(session_context)
    await dispatcher.dispatch_requests(message)
"""

import json
import traceback
from typing import TYPE_CHECKING, Any

from config.logger import setup_logging
from core.context.event_bus import Event
from core.context.event_types import EventTypes
from core.models.message_models import MessageInfo, RequestParser
import numpy as np

if TYPE_CHECKING:
    from core.session.session_context import SessionContext

TAG = __name__


class EventDispatcher:
    """
    高性能消息分发器 - 专注于消息分发和事件任务发布

    优化特性：
    - 零循环开销：直接映射，消除O(n)遍历
    - 类型优先：先判断消息类型，减少无效检查
    - 精确匹配：每个消息类型只检查对应的处理器
    - 映射表优化：使用字典映射消除多个方法调用
    """

    # 消息类型到事件类型的映射表 - 高性能O(1)查找
    MESSAGE_TYPE_TO_EVENT_MAP = {
        "request.hello": EventTypes.CLIENT_HANDSHAKE_REQUESTED,
        "request.abort": EventTypes.CLIENT_ABORT_REQUESTED,
        "request.mute": EventTypes.CLIENT_MUTE_REQUESTED,
        "request.listen": EventTypes.AUDIO_LISTEN_REQUESTED,
        "request.read": EventTypes.TEXT_READ_REQUESTED,
        "request.config": EventTypes.CONFIG_UPDATE_REQUESTED,
    }

    def __init__(self, context: "SessionContext"):
        """
        构造消息分发器
        :param context: 会话上下文
        """
        self.context = context
        self.event_bus = context.event_bus
        self.session_id = context.session_id
        self.logger = setup_logging()
        self._preview_request_id = None

        # 初始化事件处理器
        self._initialize_event_handlers()

    def _initialize_event_handlers(self) -> None:
        """
        初始化所有事件处理器
        :return: 该方法无返回值
        """
        # 延迟导入以避免循环依赖
        from core.events.audio_bytes_parse_handler import AudioBytesParseHandler
        from core.events.audio_listen_handler import AudioListenHandler
        from core.events.client_abort_handler import ClientAbortHandler
        from core.events.client_handshake_handler import ClientHandshakeHandler
        from core.events.client_mute_handler import ClientMuteHandler
        from core.events.config_update_handler import ConfigUpdateHandler
        from core.events.text_read_handler import TextReadHandler

        # 创建事件处理器实例
        self.text_read_handler = TextReadHandler(self.context)
        self.audio_bytes_parse_handler = AudioBytesParseHandler(self.context)
        self.audio_listen_handler = AudioListenHandler(self.context)
        self.client_handshake_handler = ClientHandshakeHandler(self.context)
        self.client_abort_handler = ClientAbortHandler(self.context)
        self.client_mute_handler = ClientMuteHandler(self.context)
        self.config_update_handler = ConfigUpdateHandler(self.context)

    async def dispatch_requests(self, message: Any) -> None:
        """
        分发消息 - 核心功能，统一处理所有消息类型
        :param message: 原始消息，支持多种类型（str、dict、bytes等）
        :return: 该方法无返回值
        """
        try:
            # 使用统一路由处理所有消息类型
            await self._route_message(message)

        except json.JSONDecodeError as e:
            self.logger.bind(tag=TAG).error(f"JSON解析错误: {e}, trace: {traceback.format_exc()}")
        except Exception as e:
            self.logger.bind(tag=TAG).error(f"消息分发错误: {e}, trace: {traceback.format_exc()}")

    def _create_event(self, event_type: str, data: Any) -> Event:
        """
        创建事件对象 - 统一的事件创建方法
        :param event_type: 事件类型
        :param data: 事件数据
        :return: 事件对象
        """
        return Event(
            event_type=event_type,
            session_id=self.session_id,
            data=data,
        )

    async def _route_message(self, message: Any) -> None:
        """
        路由消息到对应的事件处理器 - 高性能直接映射版本
        :param message: 原始消息，支持多种类型（str、dict、bytes等）
        :return: 该方法无返回值
        """
        try:
            # 字节消息直接处理
            if isinstance(message, bytes) or isinstance(message, np.ndarray):
                # 获取当前会话请求的id
                current_session_request_id = self.context.state_manager.current_session_request_id
                message_info = MessageInfo.create_audio_bytes_message_info(message, current_session_request_id)
                await self.event_bus.publish(self._create_event(EventTypes.AUDIO_BYTES_PARSE_REQUESTED, message_info))

            # JSON消息处理 - 使用映射表优化
            elif isinstance(message, (str, dict)):
                self.logger.bind(tag=TAG).info("=========================收到JSON消息===========================")
                # 解析JSON消息
                msg_json = message if isinstance(message, dict) else json.loads(message)
                request_message_info = RequestParser.parse_request(msg_json)

                # 非空校验
                if not request_message_info:
                    self.logger.bind(tag=TAG).warning(f"无法解析JSON消息: {msg_json}")
                    return

                # 更新请求当前id标识
                session_request_id = request_message_info.session.session_request_id
                self.context.state_manager.update_current_session_request_id(session_request_id)

                # 使用映射表查找事件类型
                event_type = self.MESSAGE_TYPE_TO_EVENT_MAP.get(request_message_info.type)
                if event_type:
                    await self.event_bus.publish(self._create_event(event_type, request_message_info))
                    self.logger.bind(tag=TAG).info(
                        f"当前:{session_request_id},已分发{request_message_info.type},请求事件:{msg_json}"
                    )
                else:
                    self.logger.bind(tag=TAG).warning(f"未知的JSON消息类型: {request_message_info.type}")

            else:
                # 未知消息类型
                self.logger.bind(tag=TAG).warning(f"未知消息类型: {type(message)}, message: {message}")

        except Exception:
            self.logger.bind(tag=TAG).error(f"消息路由错误: {traceback.format_exc()}")
