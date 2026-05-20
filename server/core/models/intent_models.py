"""
意图识别数据模型

定义意图识别过程中使用的数据结构和类型。
"""

from dataclasses import dataclass
from typing import Any, Dict, Optional

from .plugin_types import CallType


@dataclass
class IntentCall:
    """意图调用对象

    包含LLM识别出的具体调用信息，只包含执行必需的字段。

    Args:
        call_type: 调用类型（系统函数、MCP工具、IOT工具）
        name: 调用的函数或工具名称
        arguments: 调用参数字典
    """

    call_type: CallType
    name: str
    arguments: Dict[str, Any]


@dataclass
class IntentResult:
    """意图识别结果

    封装意图解析的结果，只负责解析结果，不包含业务验证。

    Args:
        intent_call: 解析出的意图调用对象，None表示解析失败或无意图
        parse_error: 解析过程中的错误信息，None表示解析成功
        raw_llm_response: LLM的原始响应，用于调试和错误追踪
    """

    intent_call: Optional[IntentCall]
    parse_error: Optional[str] = None
    raw_llm_response: str = ""
