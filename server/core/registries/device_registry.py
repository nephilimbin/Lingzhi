"""
设备类型注册表管理

管理IOT设备类型及其函数映射关系的注册表。
"""

from typing import Any, Dict

from core.models.function_models import FunctionItem


class DeviceTypeRegistry:
    """
    设备类型注册表

    用于管理IOT设备类型及其函数映射关系。

    Attributes:
        type_functions: 设备类型到函数映射的字典
    """

    def __init__(self) -> None:
        """初始化设备类型注册表"""
        self.type_functions: Dict[str, Dict[str, FunctionItem]] = {}

    def generate_device_type_id(self, descriptor: Dict[str, Any]) -> str:
        """
        通过设备能力描述生成类型ID

        Args:
            descriptor: 设备能力描述符，包含name、properties、methods等字段

        Returns:
            设备类型唯一标识符
        """
        properties = sorted(descriptor["properties"].keys())
        methods = sorted(descriptor["methods"].keys())
        # 使用属性和方法的组合作为设备类型的唯一标识
        type_signature = f"{descriptor['name']}:{','.join(properties)}:{','.join(methods)}"
        return type_signature

    def get_device_functions(self, type_id: str) -> Dict[str, FunctionItem]:
        """
        获取设备类型对应的所有函数

        Args:
            type_id: 设备类型ID

        Returns:
            设备类型对应的函数字典
        """
        return self.type_functions.get(type_id, {})

    def register_device_type(self, type_id: str, functions: Dict[str, FunctionItem]) -> None:
        """
        注册设备类型及其函数

        Args:
            type_id: 设备类型ID
            functions: 设备类型对应的函数字典
        """
        if type_id not in self.type_functions:
            self.type_functions[type_id] = functions
