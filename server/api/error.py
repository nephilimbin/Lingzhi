"""
统一错误处理模块

提供WebSocket和HTTP API的统一错误响应格式，
包括错误码定义、错误消息生成等功能。
"""

from datetime import datetime
from enum import Enum
from typing import Any, Dict, Optional


class ErrorCodes(Enum):
    """错误码枚举"""

    # 认证相关错误
    AUTH_FAILED = "AUTH_FAILED"
    AUTH_TOKEN_INVALID = "AUTH_TOKEN_INVALID"
    AUTH_DEVICE_NOT_ALLOWED = "AUTH_DEVICE_NOT_ALLOWED"
    AUTH_TOKEN_EXPIRED = "AUTH_TOKEN_EXPIRED"

    # 会话相关错误
    SESSION_INVALID = "SESSION_INVALID"
    SESSION_NOT_FOUND = "SESSION_NOT_FOUND"
    SESSION_EXPIRED = "SESSION_EXPIRED"
    SESSION_ACCESS_DENIED = "SESSION_ACCESS_DENIED"

    # 服务相关错误
    SERVICE_ERROR = "SERVICE_ERROR"
    SERVICE_UNAVAILABLE = "SERVICE_UNAVAILABLE"
    SERVICE_TIMEOUT = "SERVICE_TIMEOUT"

    # 连接相关错误
    CONNECTION_ERROR = "CONNECTION_ERROR"
    CONNECTION_TIMEOUT = "CONNECTION_TIMEOUT"
    CONNECTION_LIMIT_EXCEEDED = "CONNECTION_LIMIT_EXCEEDED"

    # 请求相关错误
    INVALID_REQUEST = "INVALID_REQUEST"
    MISSING_PARAMETER = "MISSING_PARAMETER"
    INVALID_PARAMETER = "INVALID_PARAMETER"

    # 系统相关错误
    INTERNAL_ERROR = "INTERNAL_ERROR"
    CONFIGURATION_ERROR = "CONFIGURATION_ERROR"
    RESOURCE_NOT_FOUND = "RESOURCE_NOT_FOUND"


class WebSocketErrorHandler:
    """
    WebSocket错误处理器

    提供统一的WebSocket错误响应格式。
    """

    @staticmethod
    def create_error_response(
        error_code: str,
        message: str,
        details: Optional[Dict[str, Any]] = None,
        request_id: Optional[str] = None,
    ) -> Dict[str, Any]:
        """
        创建统一的WebSocket错误响应

        Args:
            error_code: 错误码
            message: 错误消息
            details: 错误详细信息
            request_id: 请求ID（用于追踪）

        Returns:
            Dict[str, Any]: 格式化的错误响应
        """
        error_response = {
            "type": "error",
            "error_code": error_code,
            "message": message,
            "timestamp": datetime.utcnow().isoformat(),
        }

        if details:
            error_response["details"] = details

        if request_id:
            error_response["request_id"] = request_id

        return error_response

    @staticmethod
    def create_auth_error(
        message: str = "认证失败", details: Optional[Dict[str, Any]] = None
    ) -> Dict[str, Any]:
        """
        创建认证错误响应

        Args:
            message: 错误消息
            details: 错误详细信息

        Returns:
            Dict[str, Any]: 认证错误响应
        """
        return WebSocketErrorHandler.create_error_response(
            error_code=ErrorCodes.AUTH_FAILED.value, message=message, details=details
        )

    @staticmethod
    def create_session_error(
        message: str = "会话无效", details: Optional[Dict[str, Any]] = None
    ) -> Dict[str, Any]:
        """
        创建会话错误响应

        Args:
            message: 错误消息
            details: 错误详细信息

        Returns:
            Dict[str, Any]: 会话错误响应
        """
        return WebSocketErrorHandler.create_error_response(
            error_code=ErrorCodes.SESSION_INVALID.value, message=message, details=details
        )

    @staticmethod
    def create_service_error(
        message: str = "服务错误", details: Optional[Dict[str, Any]] = None
    ) -> Dict[str, Any]:
        """
        创建服务错误响应

        Args:
            message: 错误消息
            details: 错误详细信息

        Returns:
            Dict[str, Any]: 服务错误响应
        """
        return WebSocketErrorHandler.create_error_response(
            error_code=ErrorCodes.SERVICE_ERROR.value, message=message, details=details
        )

    @staticmethod
    def create_connection_error(
        message: str = "连接错误", details: Optional[Dict[str, Any]] = None
    ) -> Dict[str, Any]:
        """
        创建连接错误响应

        Args:
            message: 错误消息
            details: 错误详细信息

        Returns:
            Dict[str, Any]: 连接错误响应
        """
        return WebSocketErrorHandler.create_error_response(
            error_code=ErrorCodes.CONNECTION_ERROR.value, message=message, details=details
        )


class HTTPErrorHandler:
    """
    HTTP API错误处理器

    提供统一的HTTP错误响应格式。
    """

    @staticmethod
    def create_error_response(
        error_code: str,
        message: str,
        status_code: int = 500,
        details: Optional[Dict[str, Any]] = None,
        request_id: Optional[str] = None,
    ) -> Dict[str, Any]:
        """
        创建统一的HTTP错误响应

        Args:
            error_code: 错误码
            message: 错误消息
            status_code: HTTP状态码
            details: 错误详细信息
            request_id: 请求ID（用于追踪）

        Returns:
            Dict[str, Any]: 格式化的错误响应
        """
        error_response = {
            "success": False,
            "error_code": error_code,
            "message": message,
            "timestamp": datetime.utcnow().isoformat(),
        }

        if details:
            error_response["details"] = details

        if request_id:
            error_response["request_id"] = request_id

        return error_response

    @staticmethod
    def create_not_found_error(
        resource: str = "资源", details: Optional[Dict[str, Any]] = None
    ) -> Dict[str, Any]:
        """
        创建404错误响应

        Args:
            resource: 资源名称
            details: 错误详细信息

        Returns:
            Dict[str, Any]: 404错误响应
        """
        return HTTPErrorHandler.create_error_response(
            error_code=ErrorCodes.RESOURCE_NOT_FOUND.value,
            message=f"{resource}不存在",
            status_code=404,
            details=details,
        )

    @staticmethod
    def create_bad_request_error(
        message: str = "请求参数错误", details: Optional[Dict[str, Any]] = None
    ) -> Dict[str, Any]:
        """
        创建400错误响应

        Args:
            message: 错误消息
            details: 错误详细信息

        Returns:
            Dict[str, Any]: 400错误响应
        """
        return HTTPErrorHandler.create_error_response(
            error_code=ErrorCodes.INVALID_REQUEST.value,
            message=message,
            status_code=400,
            details=details,
        )

    @staticmethod
    def create_unauthorized_error(
        message: str = "未授权访问", details: Optional[Dict[str, Any]] = None
    ) -> Dict[str, Any]:
        """
        创建401错误响应

        Args:
            message: 错误消息
            details: 错误详细信息

        Returns:
            Dict[str, Any]: 401错误响应
        """
        return HTTPErrorHandler.create_error_response(
            error_code=ErrorCodes.AUTH_FAILED.value,
            message=message,
            status_code=401,
            details=details,
        )

    @staticmethod
    def create_internal_error(
        message: str = "内部服务器错误", details: Optional[Dict[str, Any]] = None
    ) -> Dict[str, Any]:
        """
        创建500错误响应

        Args:
            message: 错误消息
            details: 错误详细信息

        Returns:
            Dict[str, Any]: 500错误响应
        """
        return HTTPErrorHandler.create_error_response(
            error_code=ErrorCodes.INTERNAL_ERROR.value,
            message=message,
            status_code=500,
            details=details,
        )


class ErrorLogger:
    """
    错误日志记录器

    提供统一的错误日志记录功能。
    """

    @staticmethod
    def log_websocket_error(
        error_code: str, message: str, connection_id: str, details: Optional[Dict[str, Any]] = None
    ):
        """
        记录WebSocket错误

        Args:
            error_code: 错误码
            message: 错误消息
            connection_id: 连接ID
            details: 错误详细信息
        """
        from config.logger import setup_logging

        logger = setup_logging()

        log_data = {"error_code": error_code, "connection_id": connection_id, "message": message}

        if details:
            log_data.update(details)

        logger.bind(tag="WEBSOCKET_ERROR").error(f"WebSocket错误: {log_data}")

    @staticmethod
    def log_http_error(
        error_code: str,
        message: str,
        request_path: str,
        method: str,
        details: Optional[Dict[str, Any]] = None,
    ):
        """
        记录HTTP错误

        Args:
            error_code: 错误码
            message: 错误消息
            request_path: 请求路径
            method: HTTP方法
            details: 错误详细信息
        """
        from config.logger import setup_logging

        logger = setup_logging()

        log_data = {
            "error_code": error_code,
            "method": method,
            "path": request_path,
            "message": message,
        }

        if details:
            log_data.update(details)

        logger.bind(tag="HTTP_ERROR").error(f"HTTP错误: {log_data}")
