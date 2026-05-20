"""
WebSocket连接状态管理模块

定义WebSocket连接状态码和异常处理机制，用于统一管理连接状态
和处理WebSocket相关的异常情况。
"""

from enum import IntEnum


class WebSocketStatus(IntEnum):
    """WebSocket连接状态码枚举

    定义WebSocket连接的各种状态，使用HTTP状态码范围：
    - 100-199: 连接状态变更中
    - 200-299: 正常工作状态
    - 300-399: 断开连接状态
    - 400-499: 客户端/网络错误
    - 500-599: 服务器内部错误
    - 600-699: 完成/清理状态
    """

    # 连接状态
    CONNECTING = 100  # 正在建立连接
    CONNECTED = 200  # 连接正常可用

    # 业务状态
    AUDIO_STREAMING = 201  # 正在传输音频数据
    AUDIO_STOPPED = 202  # 音频流已停止

    # 断开连接状态
    DISCONNECTING = 300  # 正在断开连接
    DISCONNECTED = 301  # 连接已断开

    # 错误状态
    ERROR_CONNECTION_LOST = 400  # 连接丢失
    ERROR_SEND_FAILED = 401  # 消息发送失败
    ERROR_PROTOCOL_ERROR = 402  # 协议错误
    ERROR_AUTH_FAILED = 403  # 认证失败

    # 服务器错误
    ERROR_SERVER_ERROR = 500  # 服务器内部错误

    # 完成状态
    CLEANUP_COMPLETED = 600  # 资源清理完成


class WebSocketException(Exception):
    """WebSocket相关异常基类

    封装WebSocket操作中的异常，包含状态码、错误消息和原始异常信息。
    用于上层代码根据状态码进行精确的错误处理。

    Attributes:
        status_code: WebSocket状态码，用于错误分类和处理
        message: 错误消息描述
        original_error: 原始异常对象，用于调试和日志记录
    """

    def __init__(self, status_code: WebSocketStatus, message: str, original_error: Exception = None):
        """
        初始化WebSocket异常

        Args:
            status_code: WebSocket状态码，标识异常类型
            message: 错误消息描述
            original_error: 原始异常对象，可选参数
        """
        self.status_code = status_code
        self.message = message
        self.original_error = original_error
        super().__init__(self.message)

    def __str__(self) -> str:
        """返回异常的字符串表示"""
        base_msg = f"[{self.status_code.name}] {self.message}"
        if self.original_error:
            base_msg += f" (原始异常: {type(self.original_error).__name__}: {self.original_error})"
        return base_msg

    def is_connection_error(self) -> bool:
        """判断是否为连接相关错误"""
        return self.status_code in [
            WebSocketStatus.DISCONNECTED,
            WebSocketStatus.ERROR_CONNECTION_LOST,
            WebSocketStatus.ERROR_PROTOCOL_ERROR,
        ]

    def is_recoverable(self) -> bool:
        """判断异常是否可恢复"""
        # 发送失败可能可恢复，其他连接类错误通常不可恢复
        return self.status_code == WebSocketStatus.ERROR_SEND_FAILED
