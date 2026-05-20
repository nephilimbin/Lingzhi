"""
SSL安全管理中间件

提供SSL/TLS相关的安全功能，包括：
- SSL状态检查
- 安全头设置
- 证书验证
"""

from typing import Callable

from config.logger import setup_logging
from fastapi import Request, Response
from starlette.middleware.base import BaseHTTPMiddleware

TAG = __name__
logger = setup_logging()


class SSLSecurityMiddleware(BaseHTTPMiddleware):
    """
    SSL安全管理中间件

    提供SSL相关的安全功能和配置管理。
    """

    def __init__(self, app, ssl_enabled: bool = False):
        super().__init__(app)
        self.ssl_enabled = ssl_enabled
        logger.bind(tag=TAG).info(f"SSL中间件初始化，SSL状态: {ssl_enabled}")

    async def dispatch(self, request: Request, call_next: Callable) -> Response:
        """
        处理请求，添加安全头和SSL相关检查

        Args:
            request: HTTP请求
            call_next: 下一个中间件或路由处理器

        Returns:
            Response: HTTP响应
        """
        # 调用下一个处理器
        response = await call_next(request)

        # 添加安全头
        self._add_security_headers(response)

        # 记录SSL状态（仅用于调试）
        if self.ssl_enabled:
            scheme = request.url.scheme
            if scheme == "https":
                logger.bind(tag=TAG).debug(f"HTTPS请求: {request.url}")
            else:
                logger.bind(tag=TAG).warning(f"SSL启用但收到HTTP请求: {request.url}")

        return response

    def _add_security_headers(self, response: Response) -> None:
        """
        添加安全相关的HTTP头

        Args:
            response: HTTP响应对象
        """
        # 基本安全头
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["X-XSS-Protection"] = "1; mode=block"

        # 如果启用SSL，添加HTTPS相关头
        if self.ssl_enabled:
            response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
            response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"

        # CSP头（内容安全策略）
        csp_directives = [
            "default-src 'self'",
            "script-src 'self' 'unsafe-inline' 'unsafe-eval'",  # 允许内联脚本和eval（根据需要调整）
            "style-src 'self' 'unsafe-inline'",
            "img-src 'self' data: https:",
            "font-src 'self'",
            "connect-src 'self' ws: wss:",
            "object-src 'none'",
            "media-src 'self'",
            "frame-src 'none'",
        ]
        response.headers["Content-Security-Policy"] = "; ".join(csp_directives)

    def is_ssl_request(self, request: Request) -> bool:
        """
        检查请求是否为HTTPS

        Args:
            request: HTTP请求

        Returns:
            bool: 是否为HTTPS请求
        """
        return request.url.scheme == "https"

    def get_client_certificate(self, request: Request) -> str:
        """
        获取客户端证书信息（如果启用了客户端证书验证）

        Args:
            request: HTTP请求

        Returns:
            str: 客户端证书信息
        """
        # 这里可以实现客户端证书的提取逻辑
        # 实际实现取决于具体的SSL配置
        client_cert = request.headers.get("X-Client-Certificate")
        return client_cert or ""

    def log_ssl_info(self, request: Request) -> None:
        """
        记录SSL相关信息（仅用于调试）

        Args:
            request: HTTP请求
        """
        if self.ssl_enabled:
            logger.bind(tag=TAG).debug(f"请求协议: {request.url.scheme}")
            logger.bind(tag=TAG).debug(f"请求主机: {request.headers.get('host', 'unknown')}")

            # 记录客户端IP
            client_ip = request.client.host if request.client else "unknown"
            logger.bind(tag=TAG).debug(f"客户端IP: {client_ip}")

            # 如果有代理，记录真实IP
            forwarded_for = request.headers.get("X-Forwarded-For")
            if forwarded_for:
                logger.bind(tag=TAG).debug(f"真实客户端IP: {forwarded_for}")
