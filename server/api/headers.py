"""
HTTP请求头常量定义模块

统一管理项目中所有HTTP请求头的常量定义，确保前后端一致性。
避免硬编码字符串，提高代码可维护性。

Author: Mobile-Nika Team
"""


class HttpHeaders:
    """HTTP请求头常量类

    统一定义所有HTTP请求头字段，确保前后端使用一致的header名称。
    所有常量都遵循HTTP标准命名规范。
    """

    # 会话和设备标识
    X_SESSION_ID = "x-session-id"
    DEVICE_ID = "device-id"

    # 认证相关
    AUTHORIZATION = "authorization"
    AUTHORIZATION_BEARER_PREFIX = "Bearer "

    # 标准HTTP头部
    HOST = "host"
    CONTENT_TYPE = "content-type"
    CONTENT_LENGTH = "content-length"
    ACCEPT = "accept"
    USER_AGENT = "user-agent"

    # 常用内容类型
    APPLICATION_JSON = "application/json"
    TEXT_PLAIN = "text/plain"
    MULTIPART_FORM_DATA = "multipart/form-data"

    # WebSocket特定头部
    WEBSOCKET_PROTOCOL = "websocket"
    UPGRADE = "upgrade"
    CONNECTION = "connection"
    SEC_WEBSOCKET_KEY = "sec-websocket-key"
    SEC_WEBSOCKET_VERSION = "sec-websocket-version"

    # 自定义业务头部
    CLIENT_VERSION = "client-version"
    REQUEST_ID = "request-id"
    TIMESTAMP = "timestamp"
