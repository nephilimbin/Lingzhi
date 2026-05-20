"""
函数注册表管理

管理插件函数的注册、注销和查询功能，包含装饰器机制。
"""

from typing import Any, Callable, Dict, List, Optional

from config.logger import setup_logging
from core.models.function_models import FunctionItem
from core.models.plugin_types import ToolType

TAG = __name__
logger = setup_logging()

# 全局函数注册字典
_all_function_registry: Dict[str, FunctionItem] = {}


def register_function(name: str, desc: Any, type: Optional[ToolType] = None) -> Callable:
    """
    注册函数到全局函数注册字典的装饰器

    Args:
        name: 函数名称
        desc: 函数描述
        type: 函数类型可以,

    Returns:
        装饰器函数
    """

    def decorator(func: Callable) -> Callable:
        _all_function_registry[name] = FunctionItem(name, desc, func, type)
        return func

    return decorator


def get_global_function_registry() -> Dict[str, FunctionItem]:
    """
    获取全局函数注册表

    Returns:
        全局函数注册字典
    """
    return _all_function_registry


class FunctionRegistry:
    """
    函数注册表管理器

    管理实例级别的函数注册和查询功能。
    """

    def __init__(self) -> None:
        """初始化函数注册表"""
        self.function_registry: Dict[str, FunctionItem] = {}
        self.logger = setup_logging()

    def register_function(self, name: str) -> Optional[FunctionItem]:
        """
        从全局注册表中注册函数到实例注册表

        Args:
            name: 函数名称

        Returns:
            注册的函数项，如果未找到则返回None
        """
        # 查找全局注册表中是否有对应的函数
        func = _all_function_registry.get(name)
        if not func:
            self.logger.bind(tag=TAG).error(f"函数 '{name}' 未找到")
            return None

        self.function_registry[name] = func
        self.logger.bind(tag=TAG).info(f"函数 '{name}' 注册成功")
        return func

    def unregister_function(self, name: str) -> bool:
        """
        注销函数

        Args:
            name: 函数名称

        Returns:
            注销是否成功
        """
        if name not in self.function_registry:
            self.logger.bind(tag=TAG).error(f"函数 '{name}' 未找到")
            return False

        self.function_registry.pop(name, None)
        self.logger.bind(tag=TAG).info(f"函数 '{name}' 注销成功")
        return True

    def get_function(self, name: str) -> Optional[FunctionItem]:
        """
        获取函数

        Args:
            name: 函数名称

        Returns:
            函数项，如果未找到则返回None
        """
        return self.function_registry.get(name)

    def get_function_desc(self, name: str) -> Optional[Dict[str, Any]]:
        """
        获取函数描述

        Args:
            name: 函数名称

        Returns:
            函数描述，如果未找到则返回None
        """
        func = self.function_registry.get(name)
        if func:
            return func.description
        return None

    def get_all_functions(self) -> Dict[str, FunctionItem]:
        """
        获取所有函数

        Returns:
            函数字典
        """
        return self.function_registry

    def get_all_function_desc(self) -> List[Dict[str, Any]]:
        """
        获取所有函数描述

        Returns:
            函数描述列表:[{'type': 'function', 'function': {'name': 'handle_exit_intent', 'description': '当用户想结束对话或需要退出系统时调用', 'parameters': {'type': 'object', 'properties': {'say_goodbye': {'type': 'string', 'description': '和用户友好结束对话的告别语'}}, 'required': ['say_goodbye']}}}, ...]
        """
        func_descriptions = []
        for _, func in self.function_registry.items():
            func_descriptions.append(func.description)
        return func_descriptions
