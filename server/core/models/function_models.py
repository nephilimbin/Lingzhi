"""
函数相关数据模型

包含插件系统中函数相关的数据结构和类型定义。
"""

from dataclasses import dataclass
from typing import Any, Callable

from .plugin_types import ToolType


@dataclass
class FunctionItem:
    """
    函数项数据模型

    存储插件函数的元数据信息，包括名称、描述、函数对象和类型。

    Args:
        name: 函数名称
        description: 函数描述信息, 例如functionCall格式
            {
                'type': 'function',
                'function': {
                    'name': 'handle_exit_intent',
                    'description': '当用户想结束对话或需要退出系统时调用',
                    'parameters': {
                        'type': 'object',
                        'properties': {
                            'say_goodbye': {
                                'type': 'string',
                                'description': '和用户友好结束对话的告别语'
                            }
                        },
                        'required': ['say_goodbye']
                    }
                }
            }
        func: 函数对象
        type: 函数类型
    """

    name: str
    description: Any
    func: Callable
    type: ToolType


@dataclass
class FunctionCallData:
    """
    函数调用数据模型

    存储函数调用所需的信息，包括函数名称和参数。

    Args:
        function_name: 函数名称
        arguments: 函数参数，字典格式
    """

    type: str
    function: dict
