import traceback
from typing import Any, Dict

from config.logger import setup_logging
from core.adapters.websocket_adapter import create_websocket_adapter
from core.connection.auth_middleware import AuthenticationException, AuthMiddleware
from core.container.service_container import ServiceContainer
from core.global_services import GlobalServices
from core.session.session_context import SessionContext
from core.session.session_orchestrator import SessionOrchestrator
from core.utils.module_loader import auto_import_modules
from fastapi import WebSocket

TAG = __name__

auto_import_modules("plugins.functions")


class WebSocketConnector:
    """
    WebSocket连接器 - 专注于连接管理和会话生命周期
    职责：
    1. WebSocket连接管理
    2. 认证处理
    3. 会话创建和销毁
    4. 异常处理和资源清理
    """

    def __init__(
        self,
        websocket: WebSocket,
        config: Dict[str, Any],
        vad,
        asr,
        llm,
        tts,
        vlm,
        service_container: ServiceContainer,
        session_id: str,  # 直接传入session_id参数
        channel_type: str = "text",  # 🆕 通道类型：'text' 或 'audio'
    ):
        # 基础设施
        self.websocket = websocket
        self.config = config
        self.service_container = service_container
        self.logger = setup_logging()
        self.session_id = session_id  # 保存传入的session_id
        self.channel_type = channel_type  # 🆕 保存通道类型

        # 核心服务模块（全局实例）
        self.vad = vad
        self.asr = asr
        self.llm = llm
        self.tts = tts
        self.vlm = vlm

        # 会话管理
        self.session_orchestrator = SessionOrchestrator()
        self.auth_middleware = AuthMiddleware(config)
        self.session_context = None

    async def start_connection(self):
        """处理WebSocket连接的完整生命周期"""
        try:
            # 1. 初始化会话，传入已存在的session_id
            session_info = await self.session_orchestrator.initialize_session_info(
                self.websocket,
                self.config,
                session_id=self.session_id,  # 传入已存在的session_id
            )
            # 🆕 添加channel_type到session_info，传递给SessionContext
            session_info["channel_type"] = self.channel_type

            # ✅ 安全修复：认证已在WebSocket端点提前完成，这里不再重复认证
            # 认证逻辑已移至 server/api/websocket.py 的 websocket_endpoint() 函数中
            # 这样可以确保在 websocket.accept() 之前完成认证，避免认证绕过漏洞

            # 2. 检查是否已有SessionContext（可能由WebRTC连接预先创建）
            existing_context = GlobalServices.get_active_session_context(self.session_id)

            if existing_context:
                # 复用已存在的SessionContext
                self.session_context = existing_context
                self.logger.bind(tag=TAG).info(f"🔄 复用已存在的SessionContext: {self.session_id}")
            else:
                # 创建新的会话上下文
                self.session_context = await self._create_session_context(session_info)

                # 注册SessionContext到全局管理器
                if self.session_context:
                    GlobalServices.register_session_context(self.session_id, self.session_context)

            # ✅ 注册 WebSocketAdapter 到 SessionContext（统一管理）
            if self.session_context and self.channel_type in ["text", "audio"]:
                self.session_context.register_websocket_channel(self.channel_type, self.websocket)
                self.logger.bind(tag=TAG).info(f"✅ {self.channel_type} WebSocketAdapter 已注册到 SessionContext")

            # 🆕 注册WebSocket到GlobalServices（注册原始连接，不是SessionContext的）
            if self.channel_type == "audio":
                # 🔑 关键修复：注册 self.websocket（音频WebSocket），不是 session_context.websocket
                GlobalServices.register_audio_websocket(self.session_id, self.websocket)
                self.logger.bind(tag=TAG).info("🎵 音频WebSocket已注册到GlobalServices")
            elif self.channel_type == "text":
                GlobalServices.register_text_websocket(self.session_id, self.websocket)
                self.logger.bind(tag=TAG).info("📝 文本WebSocket已注册到GlobalServices")

            # 4. 启动会话程序（根据通道类型选择启动方式）
            if self.channel_type == "text":
                # 文本通道：启动完整的SessionContext
                if self.session_context and not getattr(self.session_context, "is_running", False):
                    await self.session_context.start_session()
            elif self.channel_type == "audio":
                # 🆕 音频通道：启动轻量级监听循环
                await self._listen_audio_websocket()

        except AuthenticationException as e:
            self.logger.bind(tag=TAG).error(f"认证失败: {str(e)}")
        except Exception as e:
            self.logger.bind(tag=TAG).error(f"连接处理出错: {str(e)}, 追踪: {traceback.format_exc()}", exc_info=True)
        finally:
            await self.close_connection()

    async def _create_session_context(self, session_info: Dict[str, Any]):
        """创建会话上下文"""

        # 获取服务实例（优先使用私有容器，回退到全局服务）
        def get_service_for_session(service_name: str):
            private_container = session_info.get("private_service_container")
            if private_container and private_container.is_service_available(service_name):
                return private_container.get_service(service_name)
            else:
                # 使用全局服务实例
                if service_name == "memory":
                    return self.service_container.get_service("memory")
                else:
                    return getattr(self, service_name)

        # 动态获取所有需要的服务
        vad = get_service_for_session("vad")
        asr = get_service_for_session("asr")
        llm = get_service_for_session("llm")
        tts = get_service_for_session("tts")
        memory = get_service_for_session("memory")
        vlm = get_service_for_session("vlm")

        # 创建SessionContext并让它管理自己的线程和资源
        context = await SessionContext.create_complete_session(
            websocket=self.websocket,
            config=self.config,
            session_info=session_info,
            vad=vad,
            asr=asr,
            llm=llm,
            tts=tts,
            memory=memory,
            vlm=vlm,
        )

        return context

    async def _listen_audio_websocket(self):
        """🆕 为音频WebSocket启动简单的消息监听"""
        try:
            # 🔑 使用 self.websocket（音频WebSocket），不是 session_context.websocket
            audio_ws = create_websocket_adapter(self.websocket, self.session_id, "audio")

            self.logger.bind(tag=TAG).info(f"🎵 音频监听循环已启动: {self.session_id}")

            # 监听音频消息并转发到EventDispatcher
            async for message in audio_ws:
                try:
                    await self.session_context.event_dispatcher.dispatch_requests(message)
                except Exception as e:
                    self.logger.bind(tag=TAG).error(f"音频消息处理出错: {e}", exc_info=True)
        except Exception as e:
            self.logger.bind(tag=TAG).error(f"音频监听循环出错: {e}", exc_info=True)

    async def close_connection(self):
        """公开的关闭方法，供外部调用"""
        try:
            # 从全局管理器注销SessionContext
            if self.session_context and hasattr(self.session_context, "session_id"):
                GlobalServices.unregister_session_context(self.session_context.session_id)

            if self.session_context:
                await self.session_context.cleanup()

            # 关闭WebSocket连接
            try:
                if hasattr(self.websocket, "state") and self.websocket.state.name != "CLOSED":
                    await self.websocket.close()
                elif hasattr(self.websocket, "closed") and not self.websocket.closed:
                    await self.websocket.close()
                else:
                    # 如果无法确定状态，直接尝试关闭（忽略异常）
                    await self.websocket.close()
            except Exception:
                # 忽略关闭websocket时的异常（可能已经关闭）
                pass

            self.logger.bind(tag=TAG).info("会话资源已清理")

        except Exception as e:
            self.logger.bind(tag=TAG).error(f"清理会话资源时出错: {e}")
