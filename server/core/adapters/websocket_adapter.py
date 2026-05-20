"""
WebSocket适配器 - FastAPI WebSocket的统一接口

提供统一的WebSocket接口，专门为FastAPI WebSocket实现。
集成连接状态管理和异常处理机制。
"""

import threading
import traceback
from typing import Any, Dict, Union

from config.logger import setup_logging
from core.models.message_models import MessageEvent
from fastapi import WebSocket

from .websocket_status import WebSocketException, WebSocketStatus

TAG = __name__


class WebSocketAdapter:
    """
    WebSocket适配器类

    提供统一的WebSocket接口，专门为FastAPI WebSocket实现。
    集成连接状态管理和异常处理，支持状态码跟踪。

    Attributes:
        websocket: FastAPI WebSocket连接对象
        session_id: 会话ID标识
        _status: 当前连接状态
        _send_lock: 发送消息的异步锁
        channel_type: 通道类型（'text' 或 'audio'）🆕
    """

    def __init__(self, websocket: WebSocket, session_id: str = "", channel_type: str = "text"):
        """
        初始化WebSocket适配器

        Args:
            websocket: FastAPI WebSocket连接对象
            session_id: 会话ID标识
            channel_type: 通道类型，'text' 或 'audio'（默认为'text'）🆕
        """
        self.websocket = websocket
        self.session_id = session_id
        self.channel_type = channel_type  # 🆕 标识通道类型
        self.logger = setup_logging()
        # 使用 threading.Lock 替代 asyncio.Lock，避免跨事件循环绑定问题
        self._send_lock = threading.Lock()
        self._status = WebSocketStatus.CONNECTING  # 初始状态为连接中

    def get_status(self) -> WebSocketStatus:
        """获取当前连接状态

        Returns:
            WebSocketStatus: 当前连接状态码
        """
        return self._status

    def set_status(self, status: WebSocketStatus) -> None:
        """设置连接状态

        Args:
            status: 新的连接状态
        """
        # old_status = self._status
        self._status = status
        # if old_status != status:
        #     self.logger.bind(tag=TAG).debug(
        #         f"WebSocket状态变更: {old_status.name} -> {status.name}, session_id={self.session_id}"
        #     )

    def __aiter__(self):
        """使适配器支持异步迭代"""
        return self

    async def __anext__(self) -> Union[str, Dict[str, Any], bytes]:
        """异步迭代器的下一个消息"""
        try:
            # 使用FastAPI的标准模式获取ASGI WebSocket消息
            message = await self.websocket.receive()

            # 根据ASGI WebSocket消息格式处理
            if isinstance(message, dict) and message.get("type") == "websocket.receive":
                # 文本消息 - 返回字符串供分发器解析
                if message.get("text") is not None:
                    return message["text"]
                # 二进制消息 - 返回bytes
                elif message.get("bytes") is not None:
                    return message["bytes"]
                # 其他情况，返回原始消息
                else:
                    return message
            elif isinstance(message, dict) and message.get("type") == "websocket.disconnect":
                self.logger.bind(tag=TAG).info(f"WebSocket断开连接: {message}")
                # 设置断开连接状态
                self.set_status(WebSocketStatus.DISCONNECTED)
                # WebSocket断开连接时，直接停止迭代，不要传递给事件分发器
                raise StopAsyncIteration
            else:
                # 非标准消息，直接返回
                return message
        except StopAsyncIteration:
            # 正常的迭代结束，不需要记录错误
            raise
        except Exception as e:
            self.logger.bind(tag=TAG).error(f"WebSocket接收错误消息: {e}, traceback: {traceback.format_exc()}")
            raise StopAsyncIteration

    async def send_json(self, data: Dict[str, Any]) -> None:
        """
        发送JSON消息

        Args:
            data: 要发送的消息数据
        """
        # FastAPI WebSocket
        await self.websocket.send_json(data)

    async def send_message(self, message: dict[str, Any]) -> None:
        """
        发送消息（线程安全，带状态码处理）

        Args:
            message: 要发送的消息字典

        Raises:
            WebSocketException: 当连接状态异常或发送失败时抛出
        """
        # 线程安全的消息发送（使用 threading.Lock 可在跨事件循环场景工作）
        with self._send_lock:
            # 检查连接状态
            if not self.is_connected():
                self.set_status(WebSocketStatus.DISCONNECTED)
                raise WebSocketException(
                    WebSocketStatus.ERROR_CONNECTION_LOST, f"无法发送消息，连接已断开: session_id={self.session_id}"
                )

            try:
                # 根据消息类型设置状态
                if message.get("type") == MessageEvent.RESPONSE_TTS_AUDIO:
                    self.set_status(WebSocketStatus.AUDIO_STREAMING)

                await self.send_json(message)

                # 音频流发送完成后恢复正常状态
                if self._status == WebSocketStatus.AUDIO_STREAMING:
                    self.set_status(WebSocketStatus.CONNECTED)

            except RuntimeError as e:
                # 将原始RuntimeError转换为带状态码的异常
                if "websocket.close" in str(e) or "already completed" in str(e):
                    self.set_status(WebSocketStatus.DISCONNECTED)
                    raise WebSocketException(WebSocketStatus.DISCONNECTED, "WebSocket已关闭，消息发送失败", e)
                else:
                    self.set_status(WebSocketStatus.ERROR_SEND_FAILED)
                    raise WebSocketException(WebSocketStatus.ERROR_SEND_FAILED, f"消息发送失败: {str(e)}", e)
            except Exception as e:
                self.set_status(WebSocketStatus.ERROR_SERVER_ERROR)
                raise WebSocketException(WebSocketStatus.ERROR_SERVER_ERROR, f"服务器内部错误: {str(e)}", e)

    def is_connected(self) -> bool:
        """检查连接状态

        Returns:
            bool: 连接是否可用
        """
        # 检查状态码
        if self._status not in [WebSocketStatus.CONNECTED, WebSocketStatus.AUDIO_STREAMING]:
            return False

        try:
            # FastAPI WebSocket状态检查
            from fastapi.websockets import WebSocketState

            return self.websocket.application_state == WebSocketState.CONNECTED
        except Exception:
            # 异常情况下更新状态并返回False
            self.set_status(WebSocketStatus.ERROR_CONNECTION_LOST)
            return False


def create_websocket_adapter(
    websocket: WebSocket, session_id: str = "", channel_type: str = "text"
) -> WebSocketAdapter:
    """
    创建WebSocket适配器

    Args:
        websocket: FastAPI WebSocket连接对象
        session_id: 会话ID标识
        channel_type: 通道类型，'text' 或 'audio'（默认为'text'）🆕

    Returns:
        WebSocketAdapter实例
    """
    # 项目只使用FastAPI，直接返回适配器
    adapter = WebSocketAdapter(websocket, session_id, channel_type)  # 🆕 传递channel_type

    # 根据当前WebSocket连接状态设置初始状态
    try:
        from fastapi.websockets import WebSocketState

        if websocket.application_state == WebSocketState.CONNECTED:
            adapter.set_status(WebSocketStatus.CONNECTED)
    except Exception:
        adapter.set_status(WebSocketStatus.ERROR_CONNECTION_LOST)

    return adapter
