"""
配置更新事件处理器

处理客户端发送的 request.config 请求，更新会话的模型配置
"""

import asyncio
import time
import traceback
from typing import TYPE_CHECKING

from config.logger import setup_logging
from core.context.event_bus import Event
from core.context.event_types import EventTypes
from core.models.message_models import MessageInfo

if TYPE_CHECKING:
    from core.session.session_context import SessionContext

TAG = __name__


class ConfigUpdateHandler:
    """
    配置更新事件处理器

    处理客户端发送的 request.config 请求，负责：
    1. 更新私有配置文件中的模型配置
    2. 重新加载受影响的模型提供商（ASR、TTS、LLM等）
    3. 发送配置更新响应

    Attributes:
        context: 会话上下文对象，提供对会话资源的访问
        logger: 日志记录器
        event_bus: 事件总线，用于订阅和发布事件
    """

    def __init__(self, context: "SessionContext"):
        self.context = context
        self.logger = setup_logging()

        # 订阅配置更新事件
        if hasattr(context, "event_bus") and context.event_bus:
            self.event_bus = context.event_bus
            self._subscribe_to_events()

    def _subscribe_to_events(self) -> None:
        """
        订阅配置更新事件。
        :return: None
        """
        if self.event_bus:
            self.event_bus.subscribe(EventTypes.CONFIG_UPDATE_REQUESTED, self.handle_config_update_event)

    async def handle_config_update_event(self, event: Event) -> None:
        """
        处理配置更新事件，从事件中提取MessageInfo对象并创建可取消的异步任务。
        :param event: 配置更新事件对象，event.data包含MessageInfo
        :return: None
        """
        try:
            # 获取MessageInfo对象
            request_message_info: MessageInfo = event.data

            # 创建可取消的任务
            task = asyncio.create_task(self.handle_config_update(request_message_info))

            # 直接使用CancellationManager注册任务
            if self.context.cancellation_manager:
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
                    self.logger.bind(tag=TAG).info("配置更新任务被取消")
                    raise
            else:
                await task

        except Exception as e:
            self.logger.bind(tag=TAG).error(f"事件驱动配置更新错误: {e}", exc_info=True)

    async def handle_config_update(self, message_info: MessageInfo) -> None:
        """
        处理配置更新请求，从MessageInfo中提取模型配置数据并执行更新操作。
        :param message_info: 消息信息对象，包含session.model_config数据
        :return: None
        """
        try:
            # 提取模型配置数据
            if not message_info.session:
                raise ValueError("缺少会话信息")

            model_config = message_info.session.model_config
            if not model_config:
                raise ValueError("缺少模型配置数据")

            # 更新私有配置
            await self._update_private_config(model_config)

            # 重新加载受影响的模型服务
            reload_results = await self._update_private_providers(model_config)

            # 发送成功响应
            success_count = sum(1 for result in reload_results.values() if result)
            total_count = len(reload_results)
            if success_count == total_count:
                message = f"配置更新成功，所有 {total_count} 个模型已重新加载"
            elif success_count > 0:
                message = f"配置部分更新成功，{success_count}/{total_count} 个模型已重新加载"
            else:
                message = "配置更新失败，所有模型重新加载均失败"

            await self._send_config_response(success=success_count > 0, message=message)

            self.logger.bind(tag=TAG).info(f"配置更新完成: {model_config}, 重新加载结果: {reload_results}")

        except Exception as e:
            self.logger.bind(tag=TAG).error(f"配置更新失败: {e}, trace: {traceback.format_exc()}")
            await self._send_config_response(success=False, message=f"配置更新失败: {str(e)}")

    async def _update_private_config(self, model_config: dict) -> None:
        """
        更新私有配置文件，将新的模型配置合并到现有配置中并持久化。
        :param model_config: 模型配置字典，键为模块类型，值为模型名称。格式: {'ASR': 'QwenASR', 'VAD': 'SileroVAD'}。支持的模块类型: ASR, TTS, LLM, VAD, VLM, Memory, Intent
        :return: None
        """
        try:
            # 获取私有配置管理器
            private_configer = self.context.private_configer
            if not private_configer:
                raise ValueError("私有配置管理器未初始化")

            self.logger.bind(tag=TAG).info(f"私有配置路径: {private_configer.config_path}")

            # 获取当前已存在的配置，进行合并更新
            existing_modules = private_configer.private_config.get("selected_module", {})

            # 构建更新的selected_modules字典（合并现有配置和新配置）
            selected_modules = existing_modules.copy()

            # 解析模型配置：仅支持字符串格式的模型名称
            for module_type, config_value in model_config.items():
                if isinstance(config_value, str):
                    # 直接使用模型名称
                    selected_modules[module_type] = config_value
                else:
                    self.logger.bind(tag=TAG).warning(f"不支持的配置格式: {config_value}，预期为字符串类型")

            # 更新私有配置
            if selected_modules:
                success = await private_configer.update_config(
                    selected_modules=selected_modules, prompt=private_configer.private_config.get("prompt", "")
                )

                if success:
                    self.logger.bind(tag=TAG).info("私有配置已成功更新")
                else:
                    self.logger.bind(tag=TAG).error("私有配置更新失败")

            else:
                self.logger.bind(tag=TAG).warning("没有有效的模型配置需要更新")

        except Exception as e:
            self.logger.bind(tag=TAG).error(f"更新私有配置失败: {e}, trace: {traceback.format_exc()}")
            raise

    async def _send_config_response(self, success: bool, message: str) -> None:
        """
        发送配置更新响应，构建标准的响应消息并通过WebSocket发送给客户端。
        :param success: 配置更新是否成功
        :param message: 响应消息，包含成功/失败的详细信息
        :return: None
        """
        try:
            # 构建响应消息
            response_data = {
                "type": "response.config",
                "version": 1,
                "transport": "websocket",
                "session": {
                    "session_id": self.context.session_id,
                    "success": success,
                    "message": message,
                    "timestamp": int(time.time()),
                },
            }

            # 发送响应
            await self.context.text_websocket.send_json(response_data)

        except Exception as e:
            self.logger.bind(tag=TAG).error(f"发送配置响应失败: {e}")

    async def _update_private_providers(self, model_config: dict) -> dict:
        """
        重新加载受影响的模型提供商，根据模型配置更新重新初始化受影响的提供商服务。
        :param model_config: 模型配置字典，键为配置类型，值为模型名称。格式: {'ASR': 'QwenASR', 'VAD': 'SileroVAD', 'Intent': 'OpenAI'}。支持的配置类型会被映射到对应的提供商类型
        :return: 重新加载结果，键为提供商类型（小写），值为是否成功。格式: {'asr': True, 'tts': False, 'llm': True, 'intent': True}
        """
        reload_results = {}

        try:
            # 配置键到提供商类型的映射表
            # 注意: Intent 使用与 LLM 相同的模型列表，Intent 配置更新时会重新初始化 IntentManager
            config_to_provider_map = {
                "ASR": "asr",
                "TTS": "tts",
                "LLM": "llm",
                "VAD": "vad",
                "VLM": "vlm",
                "Memory": "memory",
                "Intent": "intent",
            }

            # 遍历模型配置，重新加载每个受影响的提供商
            for config_key, provider_name in model_config.items():
                provider_type = config_to_provider_map.get(config_key)
                if not provider_type:
                    self.logger.bind(tag=TAG).warning(f"未知的配置键: {config_key}，跳过重新加载")
                    continue

                try:
                    # 调用 SessionContext 的重新加载方法
                    reload_success = await self.context.reload_provider(provider_type)
                    reload_results[provider_type] = reload_success

                    if reload_success:
                        self.logger.bind(tag=TAG).info(f"提供商 {provider_type} 重新加载成功")
                    else:
                        self.logger.bind(tag=TAG).error(f"提供商 {provider_type} 重新加载失败")

                except Exception as e:
                    self.logger.bind(tag=TAG).error(
                        f"重新加载提供商 {provider_type} 时出错: {e}, trace: {traceback.format_exc()}"
                    )
                    reload_results[provider_type] = False

            self.logger.bind(tag=TAG).info(f"提供商重新加载完成，结果: {reload_results}")
            return reload_results

        except Exception as e:
            self.logger.bind(tag=TAG).error(f"重新加载提供商时发生未捕获的异常: {e}, trace: {traceback.format_exc()}")
            return reload_results
