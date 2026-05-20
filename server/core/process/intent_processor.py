"""
意图处理器模块

该模块负责处理用户输入的意图识别和执行，是整个AI助手系统的核心组件。
主要功能包括：
1. 用户意图的解析和识别
2. 意图调用的验证和执行
3. 对话历史的维护和管理
4. 不同类型工具（系统函数、MCP工具、IOT工具）的统一处理

工作流程：
用户输入 -> 意图解析 -> 验证 -> 执行 -> 结果返回
"""

import json
import traceback
from typing import TYPE_CHECKING, Optional

from core.intent.intent_parser import IntentParser
from core.models import Action, ActionResponse
from core.models.intent_models import IntentCall, IntentResult
from core.models.plugin_types import CallType
from core.process.vlm_processor import VLMProcessor, VLMProcessResult
from core.session.session_state_manager import ChatMode
from core.utils.util import set_unique_id

# Cline 风格系统在需要时动态导入
CLINE_AVAILABLE = True

if TYPE_CHECKING:
    from core.providers.llm.base import LLMResponseInfo
    from core.session.session_context import SessionContext

TAG = __name__


class IntentProcessor:
    """意图处理器 - 负责完整的意图处理流程：解析→验证→执行

    该处理器是AI助手系统的核心组件，专门处理用户输入的意图识别和执行。
    支持多种意图类型包括系统函数调用、MCP工具调用和IOT设备控制。

    主要职责：
    1. 用户输入的预处理和意图解析
    2. 意图调用的验证和权限检查
    3. 不同类型意图的统一执行和结果管理
    4. 对话历史的维护和状态管理
    5. 与其他处理器（退出、唤醒）的协同工作

    处理流程：
    用户输入 → 预处理 → 意图解析 → 验证 → 执行 → 结果返回

    与其他组件的关系：
    - ExitProcessor: 处理退出意图检测
    - WakeupProcessor: 处理唤醒词检测
    - IntentManager: 执行LLM-based意图识别
    - FunctionIntentManager: 处理系统函数调用
    - MCPIntentManager: 处理MCP工具调用

    设计模式：
    - 策略模式：根据CallType选择不同的处理策略
    - 模板方法：定义标准的意图处理流程
    - 责任链：通过优先级处理不同类型的输入
    """

    def __init__(self, context: "SessionContext"):
        self.context = context
        self.logger = context.logger
        self.session_request_id = ""
        self.vlm_processor = VLMProcessor(context)

    async def handle_client_intent(self, text: str) -> Optional[ActionResponse]:
        """
        处理用户意图的主入口函数。
        :param text: 用户输入文本
        :return: 处理结果，通过ActionResponse传递处理状态
        """

        # 开始意图处理流程
        try:
            # 优先检查退出命令 - 最高优先级处理
            exit_result = await self.context.exit_processor.process_exit_intent(text)
            if exit_result is not None:
                return exit_result

            # 检查唤醒词检测 - 次高优先级处理
            wakeup_result = await self.context.wakeup_processor.process_wakeup_detection(text)
            if wakeup_result is not None:
                return wakeup_result

            # 处理 VLM 图像（如果有），在添加用户消息之前处理，
            # 以便将视觉上下文合并到用户消息中
            vlm_result: VLMProcessResult = await self.vlm_processor.process_vlm_images(text)
            text = vlm_result.text

            # 记录用户消息到对话历史，为LLM提供上下文（此时已包含VLM视觉上下文）
            self.context.session_dialogue.add_user_message(text, session_request_id=self.session_request_id)

            # 启动音频处理管道
            if self.context.state_manager.chat_mode == ChatMode.USUAL_MODE:
                # 启动音频处理管道
                self.context.tts_pipeline.start_tts_pipeline_threads()

            # 使用LLM进行意图识别和分析
            intent_response_info = await self.context.intent_manager.detect_intent(text)
            intent_result = await self._process_intent_result(intent_response_info)

            return intent_result

        except Exception as e:
            # 统一异常处理，记录错误日志并返回错误响应
            error_msg = f"意图处理失败: {e}"
            self.logger.bind(tag=TAG).error(
                f"{error_msg}\n{traceback.format_exc()}",
            )
            return ActionResponse(action=Action.ERROR, result=error_msg, response=error_msg)

    async def _process_intent_result(
        self,
        intent_response_info: "LLMResponseInfo",
    ) -> ActionResponse:
        """
        处理意图识别结果并管理对话历史。
        :param intent_response_info: LLM意图识别结果
        :return: 处理结果
        """
        try:
            # 解析LLM响应，提取意图调用信息
            intent_result: IntentResult = IntentParser.parse_llm_response(intent_response_info.content)
            self.logger.bind(tag=TAG).info(f"意图解析结果: {intent_result}")

            # 处理解析失败情况 - 降级为常规聊天
            if intent_result.parse_error:
                self.logger.bind(tag=TAG).info(f"意图解析失败: {intent_result.parse_error}")
                # TODO: 未来需要添加工具调整或者失败的辅助信息气泡
                return ActionResponse(action=Action.REQLLM, result="continue_chat", response="")

            # 处理无意图调用的情况 - 进入常规聊天模式
            if intent_result.intent_call is None:
                self.logger.bind(tag=TAG).info("未识别到意图调用，继续聊天")
                return ActionResponse(action=Action.REQLLM, result="continue_chat", response="")

            # 验证意图调用的有效性 - 确保工具存在且可用
            validation_result = await self._validate_intent_call(intent_result.intent_call)
            if not validation_result:
                self.logger.bind(tag=TAG).info(f"意图调用验证失败: {intent_result.intent_call.name}")
                return ActionResponse(
                    action=Action.ERROR,
                    result="工具调用失败, 无法获得调用结果, 请按知道的内容回答, 如果无法确认则告诉用户并给出提示.",
                    response="",
                )

            # 处理特殊的继续聊天意图
            if intent_result.intent_call.name == "continue_chat":
                self.logger.bind(tag=TAG).info("识别为continue_chat，需要常规聊天处理")
                return ActionResponse(action=Action.REQLLM, result="continue_chat", response="")

            # 执行具体的函数调用 - 内部会记录对话历史
            return await self._handle_function_call(intent_result.intent_call, intent_response_info)

        except Exception as e:
            # 异常处理：记录错误并返回错误响应
            self.logger.bind(tag=TAG).error(f"处理意图结果时发生错误: {e}")
            return ActionResponse(action=Action.ERROR, result=f"处理意图结果时发生错误: {e}", response="")

    async def _validate_intent_call(self, intent_call: IntentCall) -> bool:
        """
        验证意图调用是否有效。
        :param intent_call: 意图调用对象
        :return: 验证是否通过
        """
        try:
            if intent_call.call_type == CallType.SYSTEM_FUNCTION:
                # 验证系统函数调用 - 检查函数是否在可用列表中
                available_functions = self.context.function_intent_manager.get_current_function_tools_with_details()
                available_function_names = [tool["name"] for tool in available_functions]
                return intent_call.name in available_function_names or intent_call.name == "continue_chat"

            elif intent_call.call_type == CallType.MCP_TOOL:
                # 验证MCP工具调用 - 检查工具是否在MCP工具列表中
                available_mcp_tools = self.context.mcp_intent_manager.get_current_mcp_tools_with_details()
                available_mcp_tool_names = [tool["name"] for tool in available_mcp_tools]
                return intent_call.name in available_mcp_tool_names

            elif intent_call.call_type == CallType.IOT_TOOL:
                # TODO: 添加IOT工具的验证逻辑，目前暂时允许所有IOT工具
                self.logger.bind(tag=TAG).info("IOT工具验证逻辑待实现，暂时允许所有IOT工具")
                return True

            # 未知调用类型，默认验证失败
            return False

        except Exception as e:
            # 验证过程中的异常处理，默认返回False
            self.logger.bind(tag=TAG).error(f"验证意图调用时发生错误: {e}")
            return False

    def _build_tool_call_base(self, tool_call_id: str, intent_call: IntentCall) -> dict:
        """
        构建工具调用基础结构（可复用的通用结构）。
        :param tool_call_id: 工具调用ID
        :param intent_call: 意图调用对象
        :return: 工具调用基础结构
        """
        # 构建符合OpenAI格式的工具调用基础结构
        return {
            "id": tool_call_id,
            "type": "function",
            "function": {
                "name": intent_call.name,
                "arguments": intent_call.arguments,  # 保持原始JSON格式
            },
        }

    async def _handle_function_call(
        self, intent_call: IntentCall, intent_response_info: "LLMResponseInfo" = None
    ) -> ActionResponse:
        """
        处理函数调用并管理对话历史。
        :param intent_call: 意图调用对象
        :param intent_response_info: LLM响应信息（可选，用于记录对话历史）
        :return: 函数调用处理结果
        """
        # 生成唯一的工具调用标识符
        tool_call_id = set_unique_id("tool_call_id")

        # 序列化函数参数为JSON格式（只序列化一次以提高性能）
        arguments_json = json.dumps(intent_call.arguments, ensure_ascii=False)

        # 构建标准格式的工具调用基础结构
        tool_call_base = self._build_tool_call_base(tool_call_id, intent_call)

        # 如果提供了LLM响应信息，需要记录助手消息到对话历史
        if intent_response_info is not None:
            # 生成助手意图说明消息
            assistant_content = f"我需要调用{intent_call.name}来帮助您。"

            # 构造对话历史专用的tool_calls结构（使用序列化的参数）
            tool_call_for_history = tool_call_base.copy()
            tool_call_for_history["function"]["arguments"] = arguments_json
            tool_calls = [tool_call_for_history]

            # 记录助手消息到对话历史，包含工具调用信息
            self.context.session_dialogue.add_assistant_message(
                content=assistant_content,
                tool_calls=tool_calls,
                llm_response_info=intent_response_info,
                session_request_id=self.session_request_id,
            )

        self.logger.bind(tag=TAG).info(f"开始执行{intent_call.call_type.value}: {intent_call.name}")

        try:
            # 根据调用类型分发到相应的处理器
            if intent_call.call_type == CallType.SYSTEM_FUNCTION:
                # 系统函数调用：执行内部业务逻辑函数
                result = await self.context.function_intent_manager.handle_llm_function_call(intent_call)
            elif intent_call.call_type == CallType.MCP_TOOL:
                # MCP工具调用：调用外部集成的MCP工具
                result = await self.context.mcp_intent_manager.handle_mcp_tool_call(intent_call)
            elif intent_call.call_type == CallType.IOT_TOOL:
                # IOT设备调用：预留接口，用于智能家居控制
                # TODO: 实现IOT工具调用逻辑
                result = ActionResponse(action=Action.RESPONSE, result="", response="IOT功能正在开发中")
            else:
                # 未知调用类型的处理
                self.logger.bind(tag=TAG).warning("未知的调用类型")
                return ActionResponse(action=Action.ERROR, result="未知的调用类型", response="")

            # 验证调用结果的有效性
            if not result or not hasattr(result, "action"):
                self.logger.bind(tag=TAG).warning(f"工具调用执行无结果: {intent_call.name}")
                return ActionResponse(action=Action.RESPONSE, result="工具调用无结果", response="")

            # 构造工具调用记录信息，用于保存到对话历史
            tool_call_info = tool_call_base.copy()
            tool_call_info["result"] = result.result

            # 将工具调用结果记录到对话历史中
            self.context.session_dialogue.add_tool_message(
                content=json.dumps(tool_call_info, ensure_ascii=False),
                tool_call_id=tool_call_id,
                session_request_id=self.session_request_id,
            )

            # 根据不同的Action类型返回相应的处理结果
            if result.action == Action.RESPONSE:
                # 直接响应结果
                self.logger.bind(tag=TAG).info(f"函数执行完成: {result.result}")
                return ActionResponse(action=Action.RESPONSE, result=result.result, response=result.response)

            elif result.action == Action.REQLLM:
                # 需要LLM进一步处理
                self.logger.bind(tag=TAG).info("函数返回Action.REQLLM，需要后续LLM处理")
                return ActionResponse(action=Action.REQLLM, result=result.result, response=result.response)

            elif result.action == Action.NOTFOUND:
                # 函数或工具未找到
                self.logger.bind(tag=TAG).info(f"函数未找到: {intent_call.name}")
                return ActionResponse(action=Action.NOTFOUND, result=result.result, response=result.response)

            elif result.action == Action.NONE:
                # 无需任何操作
                self.logger.bind(tag=TAG).info("函数返回Action.NONE，不进行任何操作")
                return ActionResponse(action=Action.NONE, result=result.result, response=result.response)

            elif result.action == Action.ERROR:
                # 执行过程中发生错误
                self.logger.bind(tag=TAG).info(f"工具调用执行结果错误: {result.action}")
                return ActionResponse(action=Action.ERROR, result=result.result, response=result.response)

        except Exception as e:
            # 工具调用过程中的异常处理
            self.logger.bind(tag=TAG).error(f"工具调用失败: {e}")
            return ActionResponse(action=Action.ERROR, result=f"工具调用失败: {e}", response="")
