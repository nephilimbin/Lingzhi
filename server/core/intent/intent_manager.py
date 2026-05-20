"""
IntentManager - 基于LLM的意图识别模块
直接使用LLM进行意图识别，无需基类继承
"""

from dataclasses import dataclass
from enum import Enum
import json
import os
import time
import traceback
from typing import TYPE_CHECKING

from config.logger import setup_logging
from core.providers.llm.base import LLMResponseInfo
from core.session.session_dialogue import AssistantMessage, SystemMessage, UserMessage

if TYPE_CHECKING:
    from core.session.session_context import SessionContext


# 添加统一的调用类型枚举
class CallType(Enum):
    CHAT = "chat"
    BASE_INTENT = "base_intent"
    SYSTEM_FUNCTION = "system_function"
    MCP_TOOL = "mcp_tool"
    IOT_TOOL = "iot_tool"  # 添加IOT工具类型


# 添加统一的调用接口配置
@dataclass
class CallConfig:
    call_type: CallType
    format_key: str  # JSON中的顶层键名
    name_key: str  # 函数/工具名称的键名
    description: str  # 类型描述
    error_message: str  # 未找到时的错误消息


# 定义统一的调用配置
CALL_CONFIGS = {
    CallType.CHAT: CallConfig(
        call_type=CallType.CHAT,
        format_key="intent",
        name_key="intent",
        description="普通对话",
        error_message="",
    ),
    CallType.BASE_INTENT: CallConfig(
        call_type=CallType.BASE_INTENT,
        format_key="intent",
        name_key="intent",
        description="基础意图",
        error_message="抱歉，没有找到对应的意图。",
    ),
    CallType.SYSTEM_FUNCTION: CallConfig(
        call_type=CallType.SYSTEM_FUNCTION,
        format_key="function_call",
        name_key="name",
        description="系统函数",
        error_message="抱歉，没有找到对应的功能。",
    ),
    CallType.MCP_TOOL: CallConfig(
        call_type=CallType.MCP_TOOL,
        format_key="function_call",  # 统一使用function_call
        name_key="name",  # 统一使用name
        description="MCP工具",
        error_message="抱歉，没有找到对应的工具。",
    ),
    CallType.IOT_TOOL: CallConfig(
        call_type=CallType.IOT_TOOL,
        format_key="function_call",  # 统一使用function_call
        name_key="name",  # 统一使用name
        description="IOT设备",
        error_message="抱歉，没有找到对应的设备功能。",
    ),
}

TAG = __name__
logger = setup_logging()


class IntentManager:
    """意图识别模块 - 直接使用LLM进行意图识别"""

    def __init__(self, context: "SessionContext"):
        """初始化IntentManager

        Args:
            config: 配置字典，包含intent_options等设置
        """

        self.context = context
        self.dialogue = context.session_dialogue
        self.llm = None

        # 初始化意图选项 - 暂时使用空列表，因为当前配置中没有intent_options
        # TODO: 如果需要intent_options配置，请在session_config.py中添加SessionIntentOptions配置类
        self.intent_options = []

        # 确保 continue_chat 意图始终存在
        if not any(option.get("name") == "continue_chat" for option in self.intent_options):
            self.intent_options.append({"name": "continue_chat", "desc": "继续聊天"})

        self.promot = self._get_intent_system_prompt()
        self._initialize_intent()

    def _initialize_intent(self):
        """初始化意图识别组件"""
        try:
            # 从运行时配置获取意图LLM名称和LLM配置
            runtime_config = self.context.session_runtime_config
            intent_config = runtime_config.session_intent_config
            llm_config = runtime_config.session_llm_config

            intent_llm_name = intent_config.intent_llm_name

            # 创建或使用主LLM
            from core.container.factories import llm_factory

            if intent_llm_name and llm_config.has_llm(intent_llm_name):
                # 如果配置了专用LLM，创建独立实例
                intent_llm_config = llm_config.get_llm_config(intent_llm_name)
                intent_llm_type = llm_config.get_llm_type(intent_llm_name)
                intent_llm = llm_factory.create_instance(intent_llm_type, intent_llm_config)
            else:
                # 否则使用主LLM
                intent_llm = self.context.llm

            # 设置IntentManager的LLM实例
            self.llm = intent_llm
            logger.bind(tag=TAG).info(f"意图识别模块初始化完成: {self.llm.model_name}")

        except Exception:
            logger.bind(tag=TAG).error(f"初始化意图识别模块失败: {traceback.format_exc()}")

    def reinitialize(self) -> bool:
        """
        重新初始化意图识别模块

        在LLM配置更新后调用此方法，以使用更新后的LLM实例

        Returns:
            bool: 重新初始化是否成功
        """
        try:
            self._initialize_intent()
            return True
        except Exception:
            logger.bind(tag=TAG).error(f"重新初始化意图识别模块失败: {traceback.format_exc()}")
            return False

    async def detect_intent(self, text: str) -> "LLMResponseInfo":
        """意图识别

        Args:
            text: 用户输入文本

        Returns:
            LLMResponseInfo: 包含意图识别结果的对象
        """
        try:
            if not self.llm:
                raise ValueError("LLM provider not set")

            # 记录整体开始时间
            total_start_time = time.time()

            # 获取当前可用的系统函数列表（不包括MCP工具）
            available_function_call_tools_details = (
                self.context.function_intent_manager.get_current_function_tools_with_details()
            )

            # 获取MCP工具列表
            available_mcp_tools_details = self.context.mcp_intent_manager.get_current_mcp_tools_with_details()

            # 生成系统提示词（区分系统函数和MCP工具）
            system_prompt = self._get_intent_system_prompt(
                available_function_call_tools_details, available_mcp_tools_details
            )
            user_prompt = self._get_intent_user_prompt()
            # logger.bind(tag=TAG).debug(f"System prompt: {system_prompt}")
            logger.bind(tag=TAG).debug(f"User prompt: {user_prompt}")

            # 调用LLM进行意图识别
            llm_start_time = time.time()

            # 使用LLM提供者的统一超时保护机制
            dialogue = [{"role": "system", "content": system_prompt}, {"role": "user", "content": user_prompt}]
            response_info = next(self.llm.chat_completion(dialogue))

            if not response_info:
                logger.bind(tag=TAG).error(f"LLM意图识别失败: {response_info.error}")
                # 返回失败的响应信息，但内容设置为默认值
                response_info.content = '{"intent": "continue_chat"}'
                return response_info
        except Exception as e:
            logger.bind(tag=TAG).error(f"LLM意图识别调用失败: {e}, 追踪: {traceback.format_exc()}")
            # 创建错误响应信息
            return LLMResponseInfo(
                model_name=getattr(self.llm, "model_name", "unknown"),
                content='{"intent": "continue_chat"}',
                error=str(e),
            )

        llm_time = time.time() - llm_start_time
        # 更新响应时间
        if not response_info.model_response_duration:
            response_info.model_response_duration = llm_time

        # 打印使用的模型信息
        model_info = getattr(self.llm, "model_name", str(self.llm.__class__.__name__))
        total_time = time.time() - total_start_time
        logger.bind(tag=TAG).debug(
            f"【意图识别性能】模型: {model_info}, 总耗时: {total_time:.4f}秒, LLM调用: {llm_time:.4f}秒, 查询: '{text}...'"
        )

        # 直接返回LLM原始响应，解析和验证由IntentProcessor负责
        return response_info

    def _create_unified_call_format(self, call_type: CallType, name: str, arguments: dict = None) -> dict:
        """
        创建统一的调用格式
        Args:
            call_type: 调用类型
            name: 函数/工具名称
            arguments: 调用参数
        Returns:
            统一格式的调用字典
        """
        config = CALL_CONFIGS[call_type]

        if call_type == CallType.CHAT:
            return {"intent": "continue_chat"}
        else:
            return {
                config.format_key: {
                    config.name_key: name,
                    "arguments": arguments or {},
                    "_type": call_type.value,
                }
            }

    def _parse_unified_call_format(self, intent_data: dict) -> tuple:
        """
        解析统一的调用格式
        Returns:
            (call_type, name, arguments, config)
        """
        # 处理普通对话
        if "intent" in intent_data:
            intent_value = intent_data.get("intent", "")
            return CallType.CHAT, intent_value, {}, CALL_CONFIGS[CallType.CHAT]

        # 处理function_call格式（包括系统函数、MCP工具和IOT工具）
        elif "function_call" in intent_data:
            call_data = intent_data["function_call"]
            name = call_data.get("name", "")
            arguments = call_data.get("arguments", {})

            # 通过_type字段判断调用类型
            call_type_str = call_data.get("_type")
            if call_type_str == "mcp_tool":
                call_type = CallType.MCP_TOOL
            elif call_type_str == "iot_tool":
                call_type = CallType.IOT_TOOL
            else:
                # 默认为系统函数
                call_type = CallType.SYSTEM_FUNCTION

            return call_type, name, arguments, CALL_CONFIGS[call_type]

        # 保持向后兼容：处理旧的mcp_tool格式
        elif "mcp_tool" in intent_data:
            mcp_data = intent_data["mcp_tool"]
            name = mcp_data.get("name", mcp_data.get("tool_name", ""))
            arguments = mcp_data.get("arguments", {})
            return CallType.MCP_TOOL, name, arguments, CALL_CONFIGS[CallType.MCP_TOOL]

        # 保持向后兼容：处理旧的iot_tool格式（如果存在）
        elif "iot_tool" in intent_data:
            iot_data = intent_data["iot_tool"]
            name = iot_data.get("name", iot_data.get("tool_name", ""))
            arguments = iot_data.get("arguments", {})
            return CallType.IOT_TOOL, name, arguments, CALL_CONFIGS[CallType.IOT_TOOL]

        else:
            # 未知格式，默认为普通对话
            return CallType.CHAT, "", {}, CALL_CONFIGS[CallType.CHAT]

    def _format_mcp_tool_prompt(self, prompt: str, mcp_tools: list, enable: bool = True) -> str:
        """
        格式化MCP工具提示词

        Args:
            prompt: 当前的提示词字符串
            mcp_tools: MCP工具信息列表
            enable: 是否启用MCP工具提示，默认为True

        Returns:
            格式化后的提示词字符串
        """
        if not enable or not mcp_tools:
            return prompt

        config = CALL_CONFIGS[CallType.MCP_TOOL]
        # prompt += "\n" + "<MCP_TOOLS>"
        prompt += "\n"
        prompt += f"## {config.description}使用说明\n"

        for tool_info in mcp_tools:
            tool_name = tool_info["name"]
            tool_desc = tool_info.get("description", "")
            prompt += f"- {tool_name}: {tool_desc}\n"

        # 添加MCP工具格式说明
        prompt += "\n"
        prompt += f"## 调用{config.description}的返回格式规范\n"
        prompt += f'{{"function_call": {{"name": "工具名", "arguments": {{"参数名": "参数值"}}, "_type": "{CallType.MCP_TOOL.value}"}}}}\n'

        # 添加具体示例
        for tool_info in mcp_tools[:2]:  # 只显示前2个作为示例
            tool_name = tool_info["name"]
            example = self._create_unified_call_format(CallType.MCP_TOOL, tool_name, {})
            prompt += f"示例: {json.dumps(example, ensure_ascii=False)}\n"

        # prompt += r"</MCP_TOOLS>"
        prompt += "\n"

        return prompt

    def _format_function_call_prompt(self, prompt: str, function_call_details: list, enable: bool = True) -> str:
        """
        格式化系统函数调用提示词

        Args:
            prompt: 当前的提示词字符串
            function_call_details: 系统函数详细信息列表
            enable: 是否启用系统函数提示，默认为True

        Returns:
            格式化后的提示词字符串
        """
        if not enable or not function_call_details:
            return prompt

        config = CALL_CONFIGS[CallType.SYSTEM_FUNCTION]
        # prompt += "\n" + "<SYSTEM_FUNCTIONS>"
        prompt += "\n"
        prompt += f"## {config.description}使用说明\n"

        # 使用详细的函数描述信息
        for func_detail in function_call_details:
            # 格式化单个函数的schema为详细的参数格式
            name = func_detail.get("name", "")
            description = func_detail.get("description", "")

            result = f"- {name}: {description}\n"

            # 添加参数信息
            result += "  Arguments:\n"
            parameters = func_detail.get("parameters", {})
            if parameters and func_detail.get("parameters_properties"):
                properties = func_detail.get("parameters_properties", {})
                required_params = func_detail.get("parameters_required", [])

                for param_name, param_info in properties.items():
                    param_type = param_info.get("type", "string")
                    param_desc = param_info.get("description", "")
                    required_marker = "必需" if param_name in required_params else "可选"

                    # 添加默认值信息
                    default_value = param_info.get("default")
                    default_info = f"，默认值为{default_value}" if default_value is not None else ""

                    result += f"  - {param_name} ({param_type}, {required_marker}): {param_desc}{default_info}\n"
            else:
                # 无参数函数
                result += "  - No arguments\n"

            prompt += result

        # 添加系统函数格式说明
        prompt += "\n"
        prompt += f"## 调用{config.description}的返回格式规范\n"
        prompt += f'{{"function_call": {{"name": "函数名", "arguments": {{"参数名": "参数值"}}, "_type": "{CallType.SYSTEM_FUNCTION.value}"}}}}\n'

        # 添加具体示例
        for func_detail in function_call_details[:2]:  # 只显示前2个作为示例
            func_name = func_detail["name"]
            example = self._create_unified_call_format(CallType.SYSTEM_FUNCTION, func_name, {})
            prompt += f"示例: {json.dumps(example, ensure_ascii=False)}\n"

        # prompt += "</SYSTEM_FUNCTIONS>"
        prompt += "\n"

        return prompt

    def _format_base_intent_prompt(self, prompt: str, intent_options: list, enable: bool = True) -> str:
        """
        格式化基础意图提示词

        Args:
            prompt: 当前的提示词字符串
            intent_options: 基础意图选项列表
            enable: 是否启用基础意图提示，默认为True

        Returns:
            格式化后的提示词字符串
        """
        if not enable:
            return prompt

        # prompt += "\n" + "<BASE_INTENTS>"
        prompt += "\n"
        config = CALL_CONFIGS[CallType.BASE_INTENT]
        prompt += f"## {config.description}使用说明\n"

        # 显示可用的意图选项
        if intent_options:
            for intent_option in intent_options:
                intent_name = intent_option.get("name", "")
                intent_desc = intent_option.get("desc", "")
                prompt += f"- {intent_name}: {intent_desc}\n"

        # 添加基础意图格式说明
        prompt += "### 基础意图\n"
        prompt += f"### 调用{config.description}的返回格式规范\n"
        if intent_options:
            for intent_option in intent_options:
                intent_name = intent_option.get("name", "")
                prompt += f'{{"intent": "{intent_name}"}}\n'
        else:
            # 默认选项
            prompt += '{"intent": "continue_chat"}\n'

        # prompt += "</BASE_INTENTS>"
        prompt += "\n"

        return prompt

    def _format_iot_tool_prompt(self, prompt: str, iot_tools: list, enable: bool = True) -> str:
        """
        格式化IOT工具提示词

        Args:
            prompt: 当前的提示词字符串
            iot_tools: IOT工具信息列表
            enable: 是否启用IOT工具提示，默认为True

        Returns:
            格式化后的提示词字符串
        """
        if not enable or not iot_tools:
            return prompt

        config = CALL_CONFIGS[CallType.IOT_TOOL]
        prompt += "<IOT_TOOLS>\n"
        prompt += f"## {config.description}使用说明\n"
        for tool_info in iot_tools:
            tool_name = tool_info.get("name", "")
            tool_desc = tool_info.get("description", "")
            prompt += f"- {tool_name}: {tool_desc}\n"

        # 添加IOT工具格式说明
        prompt += f"### 调用{config.description}\n"
        prompt += f'{{"function_call": {{"name": "设备名", "arguments": {{"参数名": "参数值"}}, "_type": "{CallType.IOT_TOOL.value}"}}}}\n'

        # 添加具体示例
        for tool_info in iot_tools[:2]:  # 只显示前2个作为示例
            tool_name = tool_info.get("name", "")
            example = self._create_unified_call_format(CallType.IOT_TOOL, tool_name, {})
            prompt += f"示例: {json.dumps(example, ensure_ascii=False)}\n"
        prompt += "</IOT_TOOLS>" + "\n"
        prompt += "\n"

        return prompt

    def _load_intent_prompt_template(self) -> str:
        """
        从模板文件加载意图识别提示词

        Returns:
            模板文件的完整内容

        Raises:
            FileNotFoundError: 模板文件不存在
            ValueError: 模板文件内容为空
            Exception: 读取模板文件时发生其他错误
        """
        # 从会话运行时配置获取模板路径
        runtime_config = self.context.session_runtime_config
        prompt_template_config = runtime_config.session_prompt_template

        # 获取意图提示词模板路径
        template_relative_path = prompt_template_config.get_intent_prompt_template_path()
        template_path = os.path.join(
            os.path.dirname(os.path.dirname(os.path.dirname(__file__))), template_relative_path
        )

        try:
            with open(template_path, "r", encoding="utf-8") as f:
                template_content = f.read().strip()

            if not template_content:
                raise ValueError("模板文件内容为空")

            return template_content

        except FileNotFoundError:
            logger.bind(tag=TAG).error(f"意图提示词模板文件不存在: {template_path}")
            raise FileNotFoundError(f"意图提示词模板文件不存在: {template_path}")
        except Exception as e:
            logger.bind(tag=TAG).error(f"读取意图提示词模板文件失败: {e}")
            raise Exception(f"读取意图提示词模板文件失败: {e}")

    def _get_intent_system_prompt(self, function_call_details=None, mcp_tools_details=None, iot_tools_info=None) -> str:
        """
        根据配置的意图选项和可用函数动态生成系统提示词
        Args:
            function_call_details: 当前可用的系统函数列表
            mcp_tools_details: MCP工具的信息列表
            iot_tools_info: IOT工具的信息列表（预留接口）
        Returns:
            格式化后的系统提示词
        """
        try:
            # 获取基础提示词
            # prompt += self.context.session_dialogue.get_system_prompt()

            # 从模板文件加载完整提示词
            prompt = self._load_intent_prompt_template()

            # 添加基础意图说明（继续聊天、退出等）
            prompt = self._format_base_intent_prompt(prompt, self.intent_options)

            # 添加系统函数说明 - 使用详细参数信息
            prompt = self._format_function_call_prompt(prompt, function_call_details)

            # 添加MCP工具说明
            prompt = self._format_mcp_tool_prompt(prompt, mcp_tools_details)

            # 添加IOT工具说明（预留接口）
            prompt = self._format_iot_tool_prompt(prompt, iot_tools_info)

            # logger.bind(tag=TAG).info(f"生成的意图识别系统提示词: {prompt}, 长度: {len(prompt)} 字符")
        except Exception as e:
            logger.bind(tag=TAG).error(f"生成意图识别系统提示词失败: {e}, 追踪: {traceback.format_exc()}")
            raise

        return prompt

    def _get_intent_user_prompt(self) -> str:
        """
        生成意图识别的用户提示词
        Returns:
            用户提示词字符串
        """
        # 构建对话历史
        user_prompt = "请分析对话历史内容及用户最新问题, 并返回用户意图类型, 历史内容如下:\n"
        # messages = []
        dialogue_history = self.dialogue.get_llm_dialogue(return_objects=True)
        for index, msg in enumerate(dialogue_history):
            # if not isinstance(msg, ToolMessage):
            #     messages.append(f"{msg.role}: {msg.content}")
            if isinstance(msg, SystemMessage):
                # user_prompt += msg.content + "\n"
                pass
            elif isinstance(msg, UserMessage):
                if index == len(dialogue_history) - 1:
                    # 最后一条用户消息，表示当前输入
                    # user_prompt += "<USER_REQUEST>\n"
                    user_prompt += f"用户请求发生时间{msg.current_time}, 当前对话内容:```{msg.content}```\n"
                    # user_prompt += "</USER_REQUEST>:\n"
                    continue
                # user_prompt += "<USER_DIALOGUE_HISTORY>\n"
                user_prompt += f"用户请求发生时间:{msg.current_time}, 历史对话内容:```{msg.content}```\n"
                # user_prompt += "</USER_DIALOGUE_HISTORY>:\n"
            elif isinstance(msg, AssistantMessage):
                # user_prompt += "<ASSISTANT_DIALOGUE_HISTORY>\n"
                user_prompt += f"助手回复发生时间:{msg.current_time}, 历史对话内容:```{msg.content}```\n"
                # user_prompt += "</ASSISTANT_DIALOGUE_HISTORY>:\n"

        # 添加当前用户输入
        # user_prompt = "<DIALOGUE_HISTORY>\n"
        # user_prompt += f"\n{chr(10).join(messages)}\n"
        # user_prompt += "</DIALOGUE_HISTORY>\n"
        return user_prompt
