"""
响应相关数据模型

包含插件系统中响应相关的数据结构和类型定义。
"""

from dataclasses import dataclass
from typing import Any

from .plugin_types import Action


@dataclass
class ActionResponse:
    """
    动作响应数据模型

    标准化插件函数执行后的响应格式，包含动作类型、结果和回复内容。

    Args:
        action: 动作类型
        result: 动作产生的结果
        response: 直接回复的内容
    """

    action: Action
    result: Any
    response: Any
