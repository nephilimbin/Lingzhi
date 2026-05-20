import asyncio
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
import os
import threading
import traceback

# 前向声明避免循环导入
from typing import TYPE_CHECKING, Any, Dict, Optional

from config.logger import setup_logging
from core.adapters.websocket_adapter import WebSocketAdapter, create_websocket_adapter
from core.context.event_bus import Event
from core.context.event_types import EventTypes
from core.intent.intent_manager import IntentManager
from core.providers.asr.base import ASRProviderBase
from core.providers.llm.base import LLMProviderBase
from core.providers.memory.base import MemoryProviderBase
from core.providers.tts.base import TTSProviderBase
from core.providers.vad.base import VADProviderBase
from core.providers.vlm.base import VLMProviderBase
from core.session.session_config import SessionRuntimeConfig
from core.session.session_dialogue import SessionDialogue

if TYPE_CHECKING:
    from config.private_config import PrivateConfiger
    from core.context.event_bus import EventBus
    from core.context.event_cancel_manager import CancellationManager
    from core.context.event_dispatcher import EventDispatcher
    from core.intent.function_intent_manager import FunctionIntentManager
    from core.intent.mcp_intent_manager import McpIntentManager
    from core.process.chat_processor import ChatProcessor
    from core.process.exit_processor import ExitProcessor
    from core.process.intent_processor import IntentProcessor
    from core.process.output_processor import OutputProcessor
    from core.process.tts_pipeline import TtsPipeline
    from core.process.wakeup_processor import WakeupProcessor
    from core.session.session_state_manager import StateManager

TAG = __name__


@dataclass
class SessionContext:
    """会话上下文 - 纯数据容器，包含具体类型标注"""

    # === 核心服务提供者 ===
    vad: VADProviderBase
    asr: ASRProviderBase
    llm: LLMProviderBase
    tts: TTSProviderBase
    memory: MemoryProviderBase
    vlm: VLMProviderBase

    # === 基础设施 ===
    config: Dict[str, Any]
    logger: Any  # Logger
    session_id: str
    prompt: str
    loop: asyncio.AbstractEventLoop
    stop_event: threading.Event
    executor: ThreadPoolExecutor
    text_websocket: Optional[WebSocketAdapter] = None  # 文本通道 WebSocket
    audio_websocket: Optional[WebSocketAdapter] = None  # 音频通道 WebSocket

    # === 会话信息 ===
    client_id: str = ""
    client_info_dir: str = ""
    client_session_dir: str = ""

    # === 私有配置 ===
    private_configer: Optional["PrivateConfiger"] = None
    is_device_verified: bool = False

    # === 对话相关 ===
    session_dialogue: Optional["SessionDialogue"] = None

    # === 运行时配置 ===
    session_runtime_config: Optional[SessionRuntimeConfig] = None

    # === 意图管理器 ===
    intent: IntentManager = field(default=None, init=False)
    intent_processor: Optional["IntentProcessor"] = field(default=None, init=False)
    function_intent_manager: Optional["FunctionIntentManager"] = field(default=None, init=False)
    mcp_intent_manager: Optional["McpIntentManager"] = field(default=None, init=False)

    # === 管理器和处理器（通过工厂方法初始化）===
    event_bus: Optional["EventBus"] = field(default=None, init=False)
    event_dispatcher: Optional["EventDispatcher"] = field(default=None, init=False)
    state_manager: Optional["StateManager"] = field(default=None, init=False)
    cancellation_manager: Optional["CancellationManager"] = field(default=None, init=False)
    chat_processor: Optional["ChatProcessor"] = field(default=None, init=False)
    tts_pipeline: Optional["TtsPipeline"] = field(default=None, init=False)
    output_processor: Optional["OutputProcessor"] = field(default=None, init=False)
    exit_processor: Optional["ExitProcessor"] = field(default=None, init=False)
    wakeup_processor: Optional["WakeupProcessor"] = field(default=None, init=False)

    # === 功能配置 ===
    iot_descriptors: Dict[str, Any] = field(default_factory=dict, init=False)

    # === 连接监听 ===
    _connection_monitor_task: Optional[asyncio.Task] = field(default=None, init=False)

    def __post_init__(self):
        """基础初始化 - 仅处理必要的数据字段"""
        # 初始化运行时配置
        self.session_runtime_config = SessionRuntimeConfig.from_config(self.config)

    def _set_session_output_directory(self):
        """设置输出内容的目录"""
        self.logger.bind(tag=TAG).info(f"设置会话保存目录: {self.client_session_dir}")
        os.makedirs(self.client_session_dir, exist_ok=True)

        # 设置TTS输出目录
        if self.tts and hasattr(self.tts, "set_output_directory") and self.client_session_dir:
            tts_output_dir = os.path.join(self.client_session_dir, "tts")
            self.tts.set_output_directory(tts_output_dir)
        else:
            self.logger.bind(tag=TAG).warning("TTS output directory not set - missing TTS or client_session_dir")

        # 设置ASR输出目录
        if self.asr and hasattr(self.asr, "set_output_directory") and self.client_session_dir:
            asr_output_dir = os.path.join(self.client_session_dir, "asr")
            self.asr.set_output_directory(asr_output_dir)
        else:
            self.logger.bind(tag=TAG).warning("ASR output directory not set - missing ASR or client_session_dir")

        # 设置VLM输出目录
        if self.vlm and hasattr(self.vlm, "set_output_directory") and self.client_session_dir:
            vlm_output_dir = os.path.join(self.client_session_dir, "vlm")
            self.vlm.set_output_directory(vlm_output_dir)
        else:
            self.logger.bind(tag=TAG).warning("VLM output directory not set - missing VLM or client_session_dir")

    @classmethod
    async def create_complete_session(
        cls,
        websocket: Any,
        config: Dict[str, Any],
        session_info: Dict[str, Any],
        vad: VADProviderBase,
        asr: ASRProviderBase,
        llm: LLMProviderBase,
        tts: TTSProviderBase,
        memory: MemoryProviderBase,
        vlm: VLMProviderBase,
    ) -> "SessionContext":
        """
        完整创建会话上下文，包括所有必要的组件初始化
        """
        # 创建基础设施
        logger = setup_logging()
        # 使用WebSocket适配器统一接口，直接传递session_id和channel_type 🆕
        session_id = session_info["session_id"]
        channel_type = session_info.get("channel_type", "text")  # 🆕 获取通道类型，默认为text
        adapted_websocket = create_websocket_adapter(websocket, session_id, channel_type)
        loop = asyncio.get_event_loop()
        stop_event = threading.Event()
        executor = ThreadPoolExecutor(max_workers=10)

        # 创建对话对象
        dialogue_context_num = config.get("dialogue_context_num", 20)
        session_dialogue = SessionDialogue(dialogue_context_num=dialogue_context_num)

        # 创建SessionContext实例
        context = cls(
            vad=vad,
            asr=asr,
            llm=llm,
            tts=tts,
            memory=memory,
            vlm=vlm,
            config=config,
            logger=logger,
            session_id=session_id,
            prompt=config["prompt"],
            loop=loop,
            stop_event=stop_event,
            executor=executor,
            text_websocket=adapted_websocket if channel_type == "text" else None,
            audio_websocket=adapted_websocket if channel_type == "audio" else None,
            client_id=session_info["client_id"],
            client_info_dir=session_info["client_info_dir"],
            client_session_dir=session_info["client_session_dir"],
            private_configer=session_info["private_config"],
            is_device_verified=session_info["is_device_verified"],
            session_dialogue=session_dialogue,
        )

        # 设置输出目录
        context._set_session_output_directory()

        # 初始化组件
        await context._initialize_components(session_info)

        # 初始化所有管理器
        context._initialize_managers()

        # 初始化异步组件
        await context._initialize_async_components()

        return context

    async def _initialize_components(self, session_info: Dict[str, Any]):
        """初始化所有组件"""
        is_session_restore = session_info.get("is_session_restore", False)
        device_id = session_info.get("device_id", "")

        # 初始化记忆
        await self._initialize_memory(device_id)

        # 初始化对话
        await self._initialize_dialogue(is_session_restore)

    async def _initialize_memory(self, device_id: str):
        """初始化记忆模块"""
        try:
            if self.memory:
                self.memory.init_memory(role_id=device_id, llm=self.llm, session_id=self.session_id)
        except Exception as e:
            self.logger.bind(tag=TAG).error(f"初始化记忆模块失败: {e}", exc_info=True)

    async def _initialize_dialogue(self, is_session_restore: bool):
        """初始化对话模块"""
        if self.session_dialogue is None:
            self.session_dialogue = SessionDialogue(
                session_id=self.session_id,
                dialogue_context_num=self.session_runtime_config.session_dialogue_config.dialogue_context_num,
            )
        else:
            # 如果dialogue已存在，确保其上下文数量设置正确
            self.session_dialogue.set_dialogue_context_num(
                self.session_runtime_config.session_dialogue_config.dialogue_context_num
            )

        try:
            # 加载提示词
            self.prompt = self.config["prompt"]

            # 如果是session恢复，尝试加载之前的对话历史
            if is_session_restore:
                dialogue_file = os.path.join(self.client_session_dir, "dialogue_history.json")
                try:
                    if self.session_dialogue.load_from_file(dialogue_file):
                        self.logger.bind(tag=TAG).info(
                            f"成功恢复对话历史，共 {len(self.session_dialogue.dialogue_message)} 条消息"
                        )
                        # 检查是否需要更新系统提示
                        system_msg = next(
                            (msg for msg in self.session_dialogue.dialogue_message if msg.role == "system"),
                            None,
                        )
                        if system_msg and system_msg.content != self.prompt:
                            # 如果系统提示发生变化，更新它
                            self.session_dialogue.set_system_prompt(self.prompt)
                    else:
                        self.logger.bind(tag=TAG).info("未找到对话历史文件，创建新对话")
                        self.session_dialogue.add_system_message(self.prompt)
                except Exception as e:
                    self.logger.bind(tag=TAG).error(f"恢复对话历史失败: {e}，创建新对话")
                    self.session_dialogue.add_system_message(self.prompt)
            else:
                # 新session，创建新对话
                self.session_dialogue.add_system_message(self.prompt)

        except Exception as e:
            self.logger.bind(tag=TAG).error(f"初始化对话模块失败: {e}")

    def register_websocket_channel(self, channel_type: str, websocket: Any) -> None:
        """
        注册 WebSocket 通道到会话上下文

        :param channel_type: 通道类型，'text' 或 'audio'
        :param websocket: FastAPI WebSocket 原始连接
        """
        adapted_ws = create_websocket_adapter(websocket, self.session_id, channel_type)

        if channel_type == "text":
            self.text_websocket = adapted_ws
            self.logger.bind(tag=TAG).debug("📝 已注册文本 WebSocketAdapter 到 SessionContext")
        elif channel_type == "audio":
            self.audio_websocket = adapted_ws
            self.logger.bind(tag=TAG).debug("🎵 已注册音频 WebSocketAdapter 到 SessionContext")

    async def _initialize_mcp_services_async(self):
        """异步初始化MCP服务，避免阻塞会话启动"""
        try:
            self.logger.bind(tag=TAG).debug("开始异步初始化MCP服务")
            await self.mcp_intent_manager.initialize_servers()
            self.logger.bind(tag=TAG).debug("MCP服务异步初始化完成")
        except Exception as e:
            self.logger.bind(tag=TAG).error(f"MCP服务异步初始化失败: {e}", exc_info=True)

    def _initialize_managers(self):
        """初始化所有管理器和处理器"""
        # 延迟导入以避免循环依赖
        from core.context.event_bus import EventBus
        from core.context.event_cancel_manager import CancellationManager
        from core.context.event_dispatcher import EventDispatcher
        from core.intent.function_intent_manager import FunctionIntentManager
        from core.intent.mcp_intent_manager import McpIntentManager
        from core.process.chat_processor import ChatProcessor
        from core.process.exit_processor import ExitProcessor
        from core.process.intent_processor import IntentProcessor
        from core.process.output_processor import OutputProcessor
        from core.process.tts_pipeline import TtsPipeline
        from core.process.wakeup_processor import WakeupProcessor
        from core.registries.function_registry import FunctionRegistry
        from core.session.session_state_manager import StateManager

        # 初始化函数注册表
        self.function_registry = FunctionRegistry()

        # 事件相关模块
        self.event_bus = EventBus()
        self.cancellation_manager = CancellationManager(self)

        # 初始化状态管理器, 需要优先创建，会影响其他模块中对通用参数的调用及相关初始化。
        self.state_manager = StateManager(self)

        # 消息处理相关模块
        self.event_dispatcher = EventDispatcher(self)
        self.intent_processor = IntentProcessor(self)
        self.exit_processor = ExitProcessor(self)
        self.chat_processor = ChatProcessor(self)
        self.tts_pipeline = TtsPipeline(self)
        self.wakeup_processor = WakeupProcessor(self)
        self.output_processor = OutputProcessor(self)

        # 初始化函数处理器
        self.intent_manager = IntentManager(self)
        self.function_intent_manager = FunctionIntentManager(self)
        self.mcp_intent_manager = McpIntentManager(self)

    async def _initialize_async_components(self):
        """初始化需要异步启动的组件"""
        try:
            # 启动异步音频处理器
            if self.tts_pipeline:
                self.tts_pipeline.start_tts_pipeline_threads()
                self.logger.bind(tag=TAG).debug("异步音频处理器已启动")

            # 可以在这里添加其他异步组件的初始化
        except Exception:
            self.logger.bind(tag=TAG).error(f"异步组件初始化失败: {traceback.format_exc()}")
            # 清理已启动的组件
            await self._cleanup_components()
            raise

    async def cleanup(self):
        """清理所有会话资源"""
        try:
            # 停止连接监听任务
            if self._connection_monitor_task and not self._connection_monitor_task.done():
                self._connection_monitor_task.cancel()
                try:
                    await self._connection_monitor_task
                except asyncio.CancelledError:
                    pass

            # 保存对话历史和记忆
            await self._save_session_data()

            # 发布会话结束事件（触发所有任务取消）
            await self.event_bus.publish(
                Event(
                    event_type=EventTypes.SESSION_TASKS_CANCEL_REQUESTED,
                    session_id=self.session_id,
                    data={"task_types": []},  # 空列表表示取消所有任务
                )
            )

            # 清理异步组件（在清理其他组件之前）
            await self._cleanup_components()

            # 等待一小段时间让任务取消完成
            await asyncio.sleep(0.1)

            # 停止事件和清理资源
            if self.stop_event:
                self.stop_event.set()

            # 关闭线程池
            if self.executor:
                self.executor.shutdown(wait=False, cancel_futures=True)

            self.logger.bind(tag=TAG).info("会话资源清理完成")

        except Exception as e:
            self.logger.bind(tag=TAG).error(f"清理会话资源时出错: {e}")

    async def _cleanup_components(self):
        """清理异步组件"""
        try:
            # 清理MCP管理器
            if self.mcp_intent_manager:
                await self.mcp_intent_manager.cleanup_all_mcp_tools()

            # 停止异步音频处理器
            if self.tts_pipeline:
                self.tts_pipeline.stop_tts_pipeline_threads()
                self.logger.bind(tag=TAG).info("异步音频处理器已停止")

            # 可以在这里添加其他异步组件的清理
        except Exception:
            self.logger.bind(tag=TAG).error(f"清理异步组件时出错: {traceback.format_exc()}")

    async def _save_session_data(self):
        """保存会话数据"""
        try:
            # 保存对话历史
            if self.session_dialogue and self.client_session_dir:
                dialogue_file = os.path.join(self.client_session_dir, "dialogue_history.json")
                try:
                    self.session_dialogue.save_to_file(dialogue_file)
                    self.logger.bind(tag=TAG).info(f"对话历史已保存到: {dialogue_file}")
                except Exception as e:
                    self.logger.bind(tag=TAG).error(f"保存对话历史失败: {e}")

            # 保存记忆
            if self.memory and hasattr(self.memory, "save_memory") and self.session_dialogue:
                self.logger.bind(tag=TAG).info("通过记忆服务保存记忆")
                await self.memory.save_memory(self.session_dialogue.dialogue_message)
            else:
                self.logger.bind(tag=TAG).warning("记忆或对话不可用，跳过记忆保存")

        except Exception as e:
            self.logger.bind(tag=TAG).error(f"保存会话数据时出错: {e}", exc_info=True)

    async def start_session(self):
        """开始处理WebSocket消息循环 - 顺序处理，避免并发导致的重复处理"""
        try:
            # 订阅WebSocket断开连接事件
            self.event_bus.subscribe(
                event_type=EventTypes.WEBSOCKET_DISCONNECTED, handler=self._handle_websocket_disconnected
            )

            # 启动连接状态监控任务
            self._connection_monitor_task = asyncio.create_task(self._monitor_connection_status())

            # 顺序处理每条消息，不使用worker队列（仅文本通道使用）
            if not self.text_websocket:
                self.logger.bind(tag=TAG).error("文本WebSocket未初始化，无法启动会话")
                return

            async for message in self.text_websocket:
                try:
                    await self.event_dispatcher.dispatch_requests(message)
                except Exception as e:
                    self.logger.bind(tag=TAG).error(f"处理消息出错: {e}", exc_info=True)

        except Exception as disconnect_error:
            # 统一处理WebSocket断开连接异常
            error_name = type(disconnect_error).__name__
            if "disconnect" in error_name.lower() or "closed" in error_name.lower():
                # 连接断开，正常退出循环
                self.logger.bind(tag=TAG).debug(f"客户端断开连接: {error_name}")
                # 发布WebSocket断开事件
                await self.event_bus.publish(
                    Event(
                        event_type=EventTypes.WEBSOCKET_DISCONNECTED,
                        session_id=self.session_id,
                        data={"reason": "connection_lost"},
                    )
                )
                return  # 使用return退出函数，而不是break
            else:
                # 其他错误，记录并重新抛出
                self.logger.bind(tag=TAG).error(f"消息处理循环出错: {disconnect_error}", exc_info=True)
                raise
        finally:
            await self.cleanup()

    async def _monitor_connection_status(self):
        """监控WebSocket连接状态"""
        while not self.stop_event.is_set():
            try:
                # 监控文本WebSocket连接状态（仅文本通道需要）
                if not self.text_websocket or not self.text_websocket.is_connected():
                    self.logger.bind(tag=TAG).info(f"检测到连接断开，触发自动清理: {self.session_id}")

                    # 发布连接断开事件（触发自动任务取消）
                    await self.event_bus.publish(
                        Event(
                            event_type=EventTypes.WEBSOCKET_DISCONNECTED,
                            session_id=self.session_id,
                            data={"reason": "monitor_detected"},
                        )
                    )
                    break

                await asyncio.sleep(0.1)  # 每100ms检查一次

            except Exception as e:
                self.logger.bind(tag=TAG).error(f"连接状态监控错误: {e}")
                break

    async def _handle_websocket_disconnected(self, event):
        """
        处理WebSocket断开事件

        Args:
            event: WebSocket断开事件对象
        """
        session_id = event.session_id

        if session_id != self.session_id:
            return

        # 使用CancellationManager取消音频任务
        if self.cancellation_manager:
            cancelled_count = await self.cancellation_manager.cancel_session_tasks(session_id=session_id, task_types=[])
            self.logger.bind(tag=TAG).info(f"已取消 {cancelled_count} 个任务")

    async def reload_provider(self, provider_type: str) -> bool:
        """
        重新加载指定类型的提供商（asr、tts、llm、vad、vlm、memory、intent等）

        :param provider_type: 提供商类型（如 "asr", "tts", "llm", "vad", "vlm", "memory", "intent"）
        :return: 是否成功重新加载
        """
        try:
            # 特殊处理：intent 不是通过服务容器管理的
            if provider_type == "intent":
                return await self._reload_intent()

            # 映射配置键到提供商属性
            provider_mapping = {
                "asr": "asr",
                "tts": "tts",
                "llm": "llm",
                "vad": "vad",
                "vlm": "vlm",
                "memory": "memory",
            }

            if provider_type not in provider_mapping:
                self.logger.bind(tag=TAG).error(f"不支持的提供商类型: {provider_type}")
                return False

            # 从全局服务容器重新加载服务
            from core.global_services import GlobalServices

            service_container = GlobalServices.get_service_container()

            # 从会话的私有配置中获取选中的模块配置
            override_selected_module = None
            if self.private_configer and self.private_configer.private_config:
                override_selected_module = self.private_configer.private_config.get("selected_module", {})

            # 使用会话的私有配置重新加载服务
            reload_success = await service_container.reload_service(
                provider_type, override_selected_module=override_selected_module
            )
            if not reload_success:
                self.logger.bind(tag=TAG).error(f"服务容器重新加载 {provider_type} 失败")
                return False

            # 获取新的服务实例
            new_provider = service_container.get_service(provider_type)
            if not new_provider:
                self.logger.bind(tag=TAG).error(f"获取新 {provider_type} 实例失败")
                return False

            # 更新SessionContext中的提供商引用
            provider_attr = provider_mapping[provider_type]

            # 设置新提供商
            setattr(self, provider_attr, new_provider)

            # 特殊处理：重新初始化需要特定设置的提供商
            if provider_type == "memory" and hasattr(new_provider, "init_memory"):
                # 重新初始化记忆，使用现有的 role_id 和 session_id
                device_id = self.private_configer.device_id if self.private_configer else ""
                new_provider.init_memory(role_id=device_id, llm=self.llm, session_id=self.session_id)
                self.logger.bind(tag=TAG).debug("Memory 提供商已重新初始化")
            self.logger.bind(tag=TAG).info(f"SessionContext 中的 {provider_type} 提供商已更新")
            return True

        except Exception:
            self.logger.bind(tag=TAG).error(f"重新加载提供商 {provider_type} 时出错: {traceback.format_exc()}")
            return False

    async def _reload_intent(self) -> bool:
        """
        重新加载 IntentManager

        IntentManager 使用与 LLM 相同的模型列表，因此当 Intent 配置更新时：
        1. 更新私有配置中的 Intent 选择
        2. 重新初始化 IntentManager 以使用新配置

        :return: 是否成功重新加载
        """
        try:
            # 重新加载运行时配置（以获取最新的 Intent 配置）
            self._reload_runtime_config()

            # 重新初始化 IntentManager
            if hasattr(self, "intent_manager") and self.intent_manager:
                reload_success = self.intent_manager.reinitialize()
                if reload_success:
                    self.logger.bind(tag=TAG).info("IntentManager 重新加载成功")
                else:
                    self.logger.bind(tag=TAG).error("IntentManager 重新加载失败")
                return reload_success
            else:
                self.logger.bind(tag=TAG).warning("IntentManager 未初始化")
                return False

        except Exception:
            self.logger.bind(tag=TAG).error(f"重新加载 IntentManager 时出错: {traceback.format_exc()}")
            return False

    def _reload_runtime_config(self) -> None:
        """
        重新加载运行时配置

        从私有配置中重新加载 selected_module，并更新 session_runtime_config
        这样可以确保 IntentManager 能获取到最新的配置
        """
        try:
            if self.private_configer and hasattr(self.private_configer, "private_config"):
                # 获取更新后的私有配置
                private_config = self.private_configer.private_config

                # 更新全局配置中的 selected_module
                if "selected_module" in private_config:
                    self.config["selected_module"] = private_config["selected_module"]

                # 重新创建运行时配置对象
                self.session_runtime_config = SessionRuntimeConfig.from_config(self.config)

        except Exception as e:
            self.logger.bind(tag=TAG).error(f"重新加载运行时配置时出错: {e}, 追踪: {traceback.format_exc()}")
