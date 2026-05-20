"""
插件系统类型定义

包含插件系统中使用的枚举类型，定义插件工具和响应动作的分类。
"""

from enum import Enum


class ToolType(Enum):
    """
    插件工具类型枚举

    定义不同类型的插件工具及其行为特征。
    """

    NONE = (1, "调用完工具后，不做其他操作")
    WAIT = (2, "调用工具，等待函数返回")
    CHANGE_SYS_PROMPT = (3, "修改系统提示词，切换角色性格或职责")
    SYSTEM_CTL = (4, "系统控制，影响正常的对话流程，如退出、播放音乐等，需要传递conn参数")
    IOT_CTL = (5, "IOT设备控制，需要传递conn参数")
    MCP_CLIENT = (6, "MCP客户端")


class CallType(Enum):
    """
    调用类型枚举

    定义意图识别中不同类型的调用方式。
    """

    SYSTEM_FUNCTION = "system_function"
    MCP_TOOL = "mcp_tool"
    IOT_TOOL = "iot_tool"


class Action(Enum):
    """
    动作响应枚举

    定义插件函数执行后的响应动作类型。
    """

    ERROR = (-1, "错误")
    NOTFOUND = (0, "没有找到函数")
    NONE = (1, "不进行操作")
    RESPONSE = (2, "直接回复")
    REQLLM = (3, "调用函数后再请求llm生成回复")
