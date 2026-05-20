"""
注册表管理模块

提供函数注册表和设备类型注册表的管理功能。
"""

from .device_registry import DeviceTypeRegistry
from .function_registry import FunctionRegistry, get_global_function_registry, register_function

# 全局设备注册表实例
device_type_registry = DeviceTypeRegistry()

__all__ = ["FunctionRegistry", "DeviceTypeRegistry", "register_function", "get_global_function_registry", "device_type_registry"]
