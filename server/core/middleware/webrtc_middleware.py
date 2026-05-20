"""
WebRTC中间件模块

验证WebRTC连接并处理SessionContext创建。
为前端传入的webrtc_id创建或查找SessionContext。
"""

import json

from config.logger import setup_logging
from core.global_services import GlobalServices
from fastapi import Request
from starlette.middleware.base import BaseHTTPMiddleware

logger = setup_logging()
TAG = __name__


class WebRTCMiddleware(BaseHTTPMiddleware):
    """
    WebRTC连接验证和SessionContext管理中间件

    功能：
    - 验证WebRTC连接是否存在激活的session
    - 为前端传入的webrtc_id创建或查找SessionContext
    - 确保WebRTC Stream Handler能找到对应的SessionContext
    """

    async def dispatch(self, request: Request, call_next):
        """中间件主要处理逻辑"""
        # 仅处理WebRTC offer路径
        if request.url.path == "/webrtc/offer" and request.method == "POST":
            body_bytes = await request.body()
            request._receive = {"type": "http.request", "body": body_bytes, "more_body": False}

            try:
                data = json.loads(body_bytes)
                webrtc_id = data.get("webrtc_id")

                if webrtc_id:
                    # 首先检查是否已有SessionContext
                    session_context = GlobalServices.get_active_session_context(webrtc_id)

                    # 如果仍然没有找到SessionContext，记录警告但不阻止请求
                    if not session_context:
                        logger.bind(tag=TAG).warning(
                            f"⚠️ 无法找到SessionContext，WebRTC连接可能无法正常工作: {webrtc_id}"
                        )

            except Exception as e:
                logger.bind(tag=TAG).error(f"❌ WebRTC中间件处理错误: {e}")

        return await call_next(request)
