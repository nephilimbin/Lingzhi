"""
全局服务管理模块

提供统一的服务容器管理和连接管理功能，
确保所有WebSocket连接共享重量级服务实例，
同时保持连接级别的会话隔离。
"""

import asyncio
from typing import TYPE_CHECKING, Any, Dict, List, Optional

from config.logger import setup_logging
from core.container.service_container import ServiceContainer

if TYPE_CHECKING:
    from core.connection.websocket_connector import WebSocketConnector
    from core.session.session_context import SessionContext
    from fastapi import WebSocket

TAG = __name__


class GlobalServices:
    """
    全局服务管理器

    负责管理：
    1. 全局共享的服务容器（VAD、ASR、LLM、TTS等重量级服务）
    2. 活跃的WebSocket连接（仅用于统计和监控）
    3. 应用生命周期管理
    """

    _instance: Optional["GlobalServices"] = None
    _service_container: Optional[ServiceContainer] = None
    _config: Optional[Dict[str, Any]] = None
    _active_connections: Dict[str, "WebSocketConnector"] = {}
    _active_session_contexts: Dict[str, "SessionContext"] = {}  # 添加SessionContext管理
    # 双WebSocket通道管理 🆕
    _text_websockets: Dict[str, "WebSocket"] = {}  # session_id -> text websocket
    _audio_websockets: Dict[str, "WebSocket"] = {}  # session_id -> audio websocket
    _logger = setup_logging()

    @classmethod
    async def initialize(cls, config: Dict[str, Any]) -> None:
        """
        初始化全局服务容器

        :param config: 服务器配置字典
        """
        cls._logger.bind(tag=TAG).info("开始初始化全局服务容器...")

        try:
            cls._config = config
            cls._service_container = ServiceContainer(config)
            cls._service_container.initialize_services()
            cls._instance = cls()
            cls._logger.bind(tag=TAG).info("全局服务容器初始化完成")

        except Exception as e:
            cls._logger.bind(tag=TAG).error(f"全局服务容器初始化失败: {e}")
            raise RuntimeError(f"GlobalServices initialization failed: {e}")

    @classmethod
    def get_service_container(cls) -> ServiceContainer:
        """
        获取全局服务容器

        :return: 全局服务容器实例
        :raises RuntimeError: 如果服务容器未初始化
        """
        if cls._service_container is None:
            raise RuntimeError("GlobalServices not initialized. Call initialize() first.")
        return cls._service_container

    @classmethod
    def get_config(cls) -> Dict[str, Any]:
        """
        获取全局配置

        :return: 全局配置字典
        :raises RuntimeError: 如果配置未初始化
        """
        if cls._config is None:
            raise RuntimeError("GlobalServices not initialized. Call initialize() first.")
        return cls._config

    @classmethod
    def register_connection(cls, connection_id: str, handler: "WebSocketConnector") -> None:
        """
        注册WebSocket连接（仅用于统计和监控）

        :param connection_id: 连接唯一标识
        :param handler: WebSocket连接处理器
        """
        cls._active_connections[connection_id] = handler
        cls._logger.bind(tag=TAG).debug(f"注册连接: {connection_id}, 当前连接数: {len(cls._active_connections)}")

    @classmethod
    def unregister_connection(cls, connection_id: str) -> None:
        """
        注销WebSocket连接

        :param connection_id: 连接唯一标识
        """
        if connection_id in cls._active_connections:
            del cls._active_connections[connection_id]
            cls._logger.bind(tag=TAG).debug(f"注销连接: {connection_id}, 当前连接数: {len(cls._active_connections)}")

    @classmethod
    def get_active_connections_count(cls) -> int:
        """
        获取当前活跃连接数

        :return: 活跃连接数
        """
        return len(cls._active_connections)

    @classmethod
    def get_connection_ids(cls) -> List[str]:
        """
        获取所有活跃连接ID

        :return: 连接ID列表
        """
        return list(cls._active_connections.keys())

    @classmethod
    def get_active_connections(cls) -> Dict[str, "WebSocketConnector"]:
        """
        获取所有活跃连接字典

        :return: 活跃连接字典 {connection_id: websocket_handler}
        :raises RuntimeError: 如果GlobalServices未初始化
        """
        if cls._instance is None:
            raise RuntimeError("GlobalServices not initialized. Call initialize() first.")
        return cls._active_connections.copy()  # 返回副本避免外部修改

    @classmethod
    def get_active_connection(cls, connection_id: str) -> Optional["WebSocketConnector"]:
        """
        获取指定连接ID的WebSocket处理器

        :param connection_id: 连接唯一标识
        :return: WebSocket处理器对象，如果连接不存在返回None
        :raises RuntimeError: 如果GlobalServices未初始化
        """
        if cls._instance is None:
            raise RuntimeError("GlobalServices not initialized. Call initialize() first.")
        return cls._active_connections.get(connection_id)

    @classmethod
    def register_session_context(cls, session_id: str, session_context: "SessionContext") -> None:
        """
        注册SessionContext到全局管理器

        :param session_id: 会话唯一标识
        :param session_context: SessionContext实例
        """
        cls._active_session_contexts[session_id] = session_context
        cls._logger.bind(tag=TAG).debug(
            f"注册SessionContext: {session_id}, 当前活跃会话数: {len(cls._active_session_contexts)}"
        )

    @classmethod
    def unregister_session_context(cls, session_id: str) -> None:
        """
        注销SessionContext

        :param session_id: 会话唯一标识
        """
        if session_id in cls._active_session_contexts:
            del cls._active_session_contexts[session_id]
            cls._logger.bind(tag=TAG).debug(
                f"注销SessionContext: {session_id}, 当前活跃会话数: {len(cls._active_session_contexts)}"
            )

    @classmethod
    def get_active_session_context(cls, session_id: str) -> Optional["SessionContext"]:
        """
        获取指定会话ID的SessionContext

        :param session_id: 会话唯一标识
        :return: SessionContext对象，如果会话不存在返回None
        :raises RuntimeError: 如果GlobalServices未初始化
        """
        if cls._instance is None:
            raise RuntimeError("GlobalServices not initialized. Call initialize() first.")
        return cls._active_session_contexts.get(session_id)

    # ==================== 双WebSocket通道管理方法 🆕 ====================

    @classmethod
    def register_text_websocket(cls, session_id: str, websocket: "WebSocket") -> None:
        """
        注册文本通道WebSocket

        :param session_id: 会话唯一标识
        :param websocket: WebSocket连接对象
        """
        cls._text_websockets[session_id] = websocket
        cls._logger.bind(tag=TAG).info(
            f"✅ 注册文本WebSocket: session_id={session_id}, 当前文本连接数: {len(cls._text_websockets)}"
        )

    @classmethod
    def register_audio_websocket(cls, session_id: str, websocket: "WebSocket") -> None:
        """
        注册音频通道WebSocket

        :param session_id: 会话唯一标识
        :param websocket: WebSocket连接对象
        """
        cls._audio_websockets[session_id] = websocket
        cls._logger.bind(tag=TAG).info(
            f"✅ 注册音频WebSocket: session_id={session_id}, 当前音频连接数: {len(cls._audio_websockets)}"
        )

    @classmethod
    def get_text_websocket(cls, session_id: str) -> Optional["WebSocket"]:
        """
        获取文本通道WebSocket

        :param session_id: 会话唯一标识
        :return: WebSocket连接对象，如果不存在返回None
        """
        return cls._text_websockets.get(session_id)

    @classmethod
    def get_audio_websocket(cls, session_id: str) -> Optional["WebSocket"]:
        """
        获取音频通道WebSocket

        :param session_id: 会话唯一标识
        :return: WebSocket连接对象，如果不存在返回None
        """
        return cls._audio_websockets.get(session_id)

    @classmethod
    def unregister_websockets(cls, session_id: str) -> None:
        """
        注销指定会话的所有WebSocket（文本和音频）

        :param session_id: 会话唯一标识
        """
        removed_text = cls._text_websockets.pop(session_id, None)
        removed_audio = cls._audio_websockets.pop(session_id, None)

        if removed_text or removed_audio:
            cls._logger.bind(tag=TAG).info(
                f"🗑️ 注销WebSocket: session_id={session_id}, "
                f"文本={removed_text is not None}, 音频={removed_audio is not None}, "
                f"剩余连接: 文本={len(cls._text_websockets)}, 音频={len(cls._audio_websockets)}"
            )

    @classmethod
    async def cleanup(cls) -> None:
        """
        清理所有连接和资源

        在应用关闭时调用，确保优雅关闭所有连接和服务。
        """
        cls._logger.bind(tag=TAG).info("开始清理全局服务...")

        # 清理双WebSocket通道 🆕
        text_ws_count = len(cls._text_websockets)
        audio_ws_count = len(cls._audio_websockets)
        if text_ws_count > 0 or audio_ws_count > 0:
            cls._logger.bind(tag=TAG).info(f"清理双WebSocket通道: 文本={text_ws_count}, 音频={audio_ws_count}")
            cls._text_websockets.clear()
            cls._audio_websockets.clear()

        # 清理活跃连接
        connection_count = len(cls._active_connections)
        if connection_count > 0:
            cls._logger.bind(tag=TAG).info(f"关闭 {connection_count} 个活跃连接...")

            for connection_id, handler in list(cls._active_connections.items()):
                try:
                    if hasattr(handler, "close") and asyncio.iscoroutinefunction(handler.close):
                        await handler.close()
                        cls._logger.bind(tag=TAG).debug(f"连接 {connection_id} 已关闭")
                except Exception as e:
                    cls._logger.bind(tag=TAG).warning(f"关闭连接 {connection_id} 时出错: {e}")

            cls._active_connections.clear()

        # 清理活跃SessionContext
        session_count = len(cls._active_session_contexts)
        if session_count > 0:
            cls._logger.bind(tag=TAG).info(f"清理 {session_count} 个活跃会话...")

            for session_id, session_context in list(cls._active_session_contexts.items()):
                try:
                    if hasattr(session_context, "cleanup") and asyncio.iscoroutinefunction(session_context.cleanup):
                        await session_context.cleanup()
                        cls._logger.bind(tag=TAG).debug(f"会话 {session_id} 已清理")
                except Exception as e:
                    cls._logger.bind(tag=TAG).warning(f"清理会话 {session_id} 时出错: {e}")

            cls._active_session_contexts.clear()

        # 关闭服务容器
        if cls._service_container:
            try:
                await cls._service_container.close_all_services()
                cls._logger.bind(tag=TAG).info("全局服务容器已关闭")
            except Exception as e:
                cls._logger.bind(tag=TAG).error(f"关闭服务容器时出错: {e}")

        # 重置状态
        cls._instance = None
        cls._service_container = None
        cls._config = None

        cls._logger.bind(tag=TAG).info("全局服务清理完成")

    @classmethod
    def get_service_status(cls) -> Dict[str, Any]:
        """
        获取服务状态信息

        :return: 服务状态信息
        """
        if cls._service_container is None:
            return {"status": "not_initialized"}

        return {
            "status": "initialized",
            "active_connections": len(cls._active_connections),
            "connection_ids": list(cls._active_connections.keys()),
            "active_sessions": len(cls._active_session_contexts),
            "session_ids": list(cls._active_session_contexts.keys()),
            "services_initialized": cls._service_container._initialized
            if hasattr(cls._service_container, "_initialized")
            else False,
        }
