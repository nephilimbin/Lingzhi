"""
自定义AI助手服务 - FastAPI统一应用

整合WebSocket和HTTP API服务，提供统一的8000端口访问。
保持所有现有功能和架构设计。
"""

import asyncio
from contextlib import asynccontextmanager
import socket
import sys

from api.config import router as config_router
from api.health import router as health_router
from api.webrtc import create_webrtc_stream
from api.websocket import router as websocket_router
from config.logger import setup_logging
from config.server_config import ServerConfiger
from core.global_services import GlobalServices
from core.middleware.ssl_middleware import SSLSecurityMiddleware
from core.middleware.webrtc_middleware import WebRTCMiddleware
from core.utils.util import check_ffmpeg_installed
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import uvicorn

TAG = __name__
logger = setup_logging()


@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    FastAPI应用生命周期管理

    处理应用启动和关闭时的初始化和清理工作。
    """
    # 启动时初始化
    try:
        logger.bind(tag=TAG).info("正在启动FastAPI应用...")

        # 验证配置文件
        ServerConfiger.validate_config_compatibility()

        # 检查FFmpeg
        check_ffmpeg_installed()

        # 加载配置
        config = ServerConfiger.load_config()

        # 初始化全局服务
        await GlobalServices.initialize(config)

        logger.bind(tag=TAG).info("FastAPI应用启动完成")

    except Exception as e:
        logger.bind(tag=TAG).error(f"FastAPI应用启动失败: {e}")
        raise

    try:
        yield  # 应用运行期间
    finally:
        # 关闭时清理
        try:
            logger.bind(tag=TAG).info("正在关闭FastAPI应用...")
            await GlobalServices.cleanup()
            logger.bind(tag=TAG).info("FastAPI应用关闭完成")
        except Exception as e:
            logger.bind(tag=TAG).error(f"FastAPI应用关闭时出错: {e}")


def create_app() -> FastAPI:
    """
    创建FastAPI应用实例

    Returns:
        FastAPI: 配置好的FastAPI应用实例
    """

    # 加载配置用于SSL设置和应用信息
    config = ServerConfiger.load_config()
    server_config = config.get("server", {})
    ssl_config = server_config.get("ssl", {})
    ssl_enabled = ssl_config.get("enabled", False)

    # 从配置读取应用信息
    app_config = server_config.get("app", {})
    app_title = app_config.get("title", "零知服务")
    app_description = app_config.get("description", "统一WebSocket和HTTP API服务")
    app_version = app_config.get("version", "1.0.0")

    # 创建FastAPI应用
    app = FastAPI(
        title=app_title,
        description=app_description,
        version=app_version,
        lifespan=lifespan,
    )

    # 添加SSL中间件 - 从配置读取SSL状态
    app.add_middleware(SSLSecurityMiddleware, ssl_enabled=ssl_enabled)
    app.add_middleware(WebRTCMiddleware)

    # 添加CORS中间件
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],  # 在生产环境中应该限制具体的域名
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    # 注册路由
    app.include_router(websocket_router, prefix="/chat/v1", tags=["WebSocket"])

    app.include_router(config_router, prefix="/api/v1/config", tags=["配置管理"])

    app.include_router(health_router, prefix="/api/v1", tags=["健康检查"])

    # 根路径
    @app.get("/")
    async def root():
        return {
            "message": app_title,
            "version": app_version,
            "status": "running",
            "endpoints": {
                "websocket": "/chat/v1/",
                "health_check": "/api/v1/health",
                "config_api": "/api/v1/config/",
                "docs": "/docs",
            },
        }

    # 创建WebRTC流处理
    webrtc_stream = create_webrtc_stream()
    webrtc_stream.mount(app)

    return app


async def wait_for_exit():
    """
    等待退出信号

    Windows和Linux兼容的退出监听机制。
    """
    loop = asyncio.get_running_loop()
    stop_event = asyncio.Event()

    if sys.platform == "win32":
        # Windows: 用 sys.stdin.read() 监听 Ctrl + C
        await loop.run_in_executor(None, sys.stdin.read)
    else:
        # Linux/macOS: 用 signal 监听 Ctrl + C
        import signal

        def stop():
            stop_event.set()

        loop.add_signal_handler(signal.SIGINT, stop)
        loop.add_signal_handler(signal.SIGTERM, stop)  # 支持 kill 进程
        await stop_event.wait()


def get_local_ip():
    """获取本机局域网IP地址"""
    try:
        # 连接到外部地址（Google DNS），获取本地IP
        # 这个方法最可靠，因为：
        # 1. 不依赖主机名解析
        # 2. 不依赖DNS配置
        # 3. 自动选择正确的网络接口
        # 4. 不会返回链路本地地址(169.254.x.x)
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect(("8.8.8.8", 80))
            local_ip = s.getsockname()[0]

            # 额外验证：确保不是本地回环或链路本地地址
            if (
                not local_ip.startswith("127.")
                and not local_ip.startswith("169.254.")
                and not local_ip.startswith("::1")
            ):
                return local_ip
            else:
                print(f"⚠️ 获取到无效IP地址: {local_ip}")
    except Exception as e:
        print(f"❌ 获取IP地址失败: {e}")
        print("🔍 可能的原因:")
        print("   - 网络连接问题")
        print("   - DNS配置问题")
        print("   - 防火墙阻止")
        print("   - 没有活动的网络接口")

        return None


async def main():
    """
    主函数 - 启动FastAPI应用
    """
    try:
        # 获取配置
        config = ServerConfiger.load_config()
        server_config = config["server"]
        host = server_config["ip"]
        port = server_config["port"]

        # 创建应用
        app = create_app()

        # 获取SSL配置
        ssl_config = server_config.get("ssl", {})
        ssl_enabled = ssl_config.get("enabled", False)

        # 显示启动信息
        logger.bind(tag=TAG).info("=" * 60)
        logger.bind(tag=TAG).info("🚀 AI助手服务启动完成!")

        # 根据SSL状态显示不同的协议
        if ssl_enabled:
            logger.bind(tag=TAG).info("🔒 SSL/TLS已启用")
            logger.bind(tag=TAG).info("🌐 服务地址: https://{}:{}/".format(host, port))
            logger.bind(tag=TAG).info("📡 WebSocket: wss://{}:{}/chat/v1/".format(host, port))
        else:
            logger.bind(tag=TAG).info("🌐 服务地址: http://{}:{}/".format(host, port))
            logger.bind(tag=TAG).info("📡 WebSocket: ws://{}:{}/chat/v1/".format(host, port))

        logger.bind(tag=TAG).info("🔧 配置API: http://{}:{}/api/v1/config/".format(host, port))
        logger.bind(tag=TAG).info("🏥 健康检查: http://{}:{}/api/v1/health".format(host, port))
        logger.bind(tag=TAG).info("📚 API文档: http://{}:{}/docs".format(host, port))
        logger.bind(tag=TAG).info(f"🔒 HTTPS局域网访问: https://{get_local_ip()}:{port}/")
        logger.bind(tag=TAG).info("=" * 60)

        # 配置uvicorn - 添加SSL支持
        uvicorn_kwargs = {"app": app, "host": host, "port": port, "log_level": "info", "access_log": True}

        # 如果启用SSL，添加证书配置
        if ssl_enabled:
            import os

            project_dir = ServerConfiger.get_project_dir()
            cert_path = ssl_config.get("cert_path", "certs/server.crt")
            key_path = ssl_config.get("key_path", "certs/server.key")
            uvicorn_kwargs["ssl_certfile"] = os.path.join(project_dir, cert_path)
            uvicorn_kwargs["ssl_keyfile"] = os.path.join(project_dir, key_path)
            logger.bind(tag=TAG).info(f"📜 SSL证书: {cert_path}")
            logger.bind(tag=TAG).info(f"🔑 SSL私钥: {key_path}")

        config_uvicorn = uvicorn.Config(**uvicorn_kwargs)

        server = uvicorn.Server(config_uvicorn)

        # 设置信号处理
        def signal_handler():
            logger.bind(tag=TAG).info("收到退出信号，正在关闭服务器...")
            server.should_exit = True

        if sys.platform != "win32":
            import signal

            loop = asyncio.get_running_loop()
            loop.add_signal_handler(signal.SIGINT, signal_handler)
            loop.add_signal_handler(signal.SIGTERM, signal_handler)
        else:
            try:
                await asyncio.Future()
            except KeyboardInterrupt:  # Ctrl‑C
                pass

        # 启动服务器
        await server.serve()

    except KeyboardInterrupt:
        logger.bind(tag=TAG).info("手动中断，程序终止。")
    except Exception as e:
        logger.bind(tag=TAG).error(f"程序运行出错: {e}", exc_info=True)
        raise


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        logger.bind(tag=TAG).info("手动中断，程序终止。")
