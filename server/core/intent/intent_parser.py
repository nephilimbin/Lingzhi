"""
意图解析器

统一处理LLM响应的解析逻辑，消除重复代码。
"""

import json
import re
from typing import Any, Dict, Optional

from core.models.intent_models import IntentCall, IntentResult
from core.models.plugin_types import CallType
from loguru import logger

TAG = __name__


class IntentParser:
    """统一的意图解析器"""

    @staticmethod
    def parse_llm_response(response: str) -> IntentResult:
        """
        解析LLM响应，返回结构化的意图结果

        Args:
            response: LLM返回的原始响应字符串

        Returns:
            IntentResult: 解析后的意图结果
        """
        # 清理响应
        cleaned_response = response.strip()

        # 尝试提取JSON部分
        intent_data = IntentParser._extract_json_content(cleaned_response)

        if intent_data is None:
            return IntentResult(
                intent_call=None, parse_error="无法从响应中提取有效的JSON内容", raw_llm_response=response
            )
        logger.bind(tag=TAG).debug(f"解析LLM响应，提取到JSON: {intent_data}")

        # 解析意图调用
        intent_call = IntentParser._parse_intent_call(intent_data)

        if intent_call is None:
            return IntentResult(
                intent_call=None, parse_error="无法从解析的数据中提取有效的意图调用", raw_llm_response=response
            )

        return IntentResult(intent_call=intent_call, parse_error=None, raw_llm_response=response)

    @staticmethod
    def _extract_json_content(text: str) -> Optional[Dict[str, Any]]:
        """
        从文本中提取并解析JSON内容

        Args:
            text: 包含JSON的文本

        Returns:
            Optional[Dict[str, Any]]: 解析后的JSON字典对象，失败返回None
        """
        # 尝试直接解析
        try:
            return json.loads(text)
        except json.JSONDecodeError:
            pass

        # 使用正则表达式提取JSON块
        json_pattern = r"\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}"
        matches = re.findall(json_pattern, text, re.DOTALL)

        # 尝试每个匹配的JSON块
        for match in matches:
            try:
                return json.loads(match)
            except json.JSONDecodeError:
                continue

        # 尝试提取markdown代码块中的JSON
        code_block_pattern = r"```(?:json)?\s*(\{.*?\})\s*```"
        code_matches = re.findall(code_block_pattern, text, re.DOTALL)

        for match in code_matches:
            try:
                return json.loads(match)
            except json.JSONDecodeError:
                continue

        return None

    @staticmethod
    def _parse_intent_call(intent_data: Dict[str, Any]) -> Optional[IntentCall]:
        """
        从解析的数据中提取意图调用信息

        Args:
            intent_data: 解析出的意图数据字典

        Returns:
            Optional[IntentCall]: 解析出的意图调用对象，失败返回None
        """
        # 处理普通聊天意图
        if "intent" in intent_data:
            intent_value = intent_data.get("intent", "")
            if intent_value and intent_value != "chat":
                return IntentCall(call_type=CallType.SYSTEM_FUNCTION, name=intent_value, arguments={})

        # 处理function_call格式
        if "function_call" in intent_data:
            call_data = intent_data["function_call"]
            name = call_data.get("name", "")
            arguments = call_data.get("arguments", {})
            call_type_str = call_data.get("_type", "system_function")

            # 映射调用类型
            call_type = IntentParser._map_call_type(call_type_str)

            if name:  # 确保有函数名
                return IntentCall(call_type=call_type, name=name, arguments=arguments or {})

        return None

    @staticmethod
    def _map_call_type(call_type_str: str) -> CallType:
        """
        映射调用类型字符串到枚举

        Args:
            call_type_str: 调用类型字符串

        Returns:
            CallType: 对应的调用类型枚举
        """
        type_mapping = {
            "system_function": CallType.SYSTEM_FUNCTION,
            "mcp_tool": CallType.MCP_TOOL,
            "iot_tool": CallType.IOT_TOOL,
        }

        return type_mapping.get(call_type_str, CallType.SYSTEM_FUNCTION)
